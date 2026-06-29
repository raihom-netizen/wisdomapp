import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'package:flutter/foundation.dart'
    show kDebugMode, kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart' hide showDatePicker;
import '../widgets/fast_text_field.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../models/user_profile.dart';
import '../models/scale_entry.dart';
import '../models/shift_location.dart';
import '../models/controle_total_config.dart';
import '../theme/app_colors.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../widgets/premium_global_message_host.dart';
import '../utils/maintenance_app_update_links.dart';
import '../widgets/maintenance_app_update_buttons.dart';
import '../services/controle_total_config_service.dart';
import '../services/sensitive_balance_preferences.dart';

import '../services/ocorrencias_service.dart';
import '../services/produtividade_config_service.dart';
import '../constants/currency_formats.dart';
import '../utils/pwa_install_helper.dart';
import '../utils/finance_shell_navigation.dart';
import '../utils/finance_transactions_realtime.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/premium_upgrade.dart';
import '../pwa_install/install_card.dart';
import '../utils/anexo_viewer_helper.dart';
import '../utils/receipt_attachment_utils.dart';
import '../utils/url_launcher_helper.dart';
import '../constants/promo_site_urls.dart';
import '../widgets/divulgacao_public_promo_card.dart';
import '../utils/date_picker_a11y.dart';
import '../widgets/agenda_em_aberto_sheet.dart';
import '../widgets/agenda_period_filter_bar.dart';
import '../widgets/month_year_resumo_header.dart';
import '../widgets/agenda_open_item_card.dart';
import '../widgets/agenda_resumo_count_card.dart';
import '../utils/scale_entry_sei_ocorrencia.dart';
import '../widgets/scale_plantao_edit_dialog.dart';
import '../services/scale_entry_agenda_edit.dart';
import '../services/agenda_reminder_delete_helper.dart';
import '../services/user_categories_service.dart';
import '../services/logs_service.dart';
import '../services/functions_service.dart';
import '../services/fixed_expense_preferences_service.dart';
import '../services/fixed_income_preferences_service.dart';
import '../constants/app_business_rules.dart';
import '../constants/app_strings.dart';
import '../services/first_time_hint_service.dart';
import '../services/transaction_save_service.dart';
import '../services/version_check_service.dart';
import '../constants/app_version.dart';
import '../utils/app_update_launcher.dart';
import '../utils/finance_server_totals.dart';
import '../utils/finance_line_opening.dart';
import '../utils/firestore_query_batched_collect.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/home_shell_layout.dart';
import '../utils/agenda_reminder_end_of_day.dart';
import '../utils/agenda_reminder_module_scope.dart';
import '../utils/finance_category_grouping.dart';
import '../widgets/finance_category_pie_panel.dart';
import '../widgets/registrar_aporte_dialog.dart';
import '../widgets/goal_contributions_sheet.dart';
import '../widgets/sheet_voltar_controls.dart';
import 'novo_lancamento_page.dart';
import '../models/smart_input_pop_result.dart';
import '../services/finance_opening_balance_service.dart';
import '../services/finance_service.dart';
import 'smart_input_screen.dart';
import '../widgets/lancamento_expresso_plantao_sheet.dart';
import '../services/yearly_commitment_repeat_service.dart';
import '../widgets/scale_month_closure_sheet.dart';
import '../models/finance_account.dart';
import '../constants/finance_bank_presets.dart';
import '../widgets/finance_bank_brand_thumb.dart';
import '../widgets/finance_premium_ui.dart';
import '../widgets/finance_confirm_payment_sheet.dart';
import '../widgets/finance_fatura_em_aberto_hub.dart';
import '../widgets/finance_credit_card_fatura_sheet.dart';
import '../services/finance_accounts_service.dart';
import '../utils/finance_account_balance_utils.dart';
import '../widgets/finance_transfer_bottom_sheet.dart';
import '../widgets/finance_transaction_edit_dialog.dart';
import '../services/relatorio_service.dart';
import '../constants/date_time_formats.dart';
import 'report_preview_screen.dart';
import 'compromisso_form_page.dart';
import 'audiencia_form_page.dart';
import '../services/agenda_reminder_edit_service.dart';
import '../services/audiencia_reminder_service.dart';
import 'finance_screen.dart' show FinanceInsightSheet, FinanceInsightScope;
import '../utils/pdf_financeiro_super_extrato.dart';
import '../utils/finance_fatura_transaction_sort.dart';
import '../widgets/finance_transaction_sort_bar.dart';
import '../widgets/shell_keyboard_bottom_pad.dart';
import '../widgets/brl_amount_text_field.dart';

/// Bora Investir — hub orçamento doméstico (abre no navegador; o site B3 bloqueia iframe).
const String _kDicasBoraInvestirUrl =
    'https://borainvestir.b3.com.br/tudo-sobre/orcamento-domestico/';

/// Meia-noite local do [d] (só calendário).
DateTime _dateOnlyLocalDash(DateTime d) => DateTime(d.year, d.month, d.day);

/// Limite superior exclusivo para `where('date', isLessThan: …)` no Firestore.
/// O último dia incluído no filtro é o dia civil de [lastDayInclusive] (ex.: 23:59 vira esse dia).
/// Evita ambiguidade de `<= 23:59:59` entre Web, Android e iOS com [Timestamp].
DateTime _firestoreExclusiveEndAfterLastDay(DateTime lastDayInclusive) =>
    _dateOnlyLocalDash(lastDayInclusive).add(const Duration(days: 1));

/// Lista vazia ou ausente em [data] = aviso para todos; caso contrário só estes UIDs.
bool _maintenanceBannerAppliesToUid(Map<String, dynamic> data, String uid) {
  final raw = data['maintenanceTargetUids'];
  if (raw is! List || raw.isEmpty) return true;
  final set =
      raw.map((e) => e.toString().trim()).where((s) => s.isNotEmpty).toSet();
  if (set.isEmpty) return true;
  return set.contains(uid);
}

/// Evita derrubar o painel se um documento da escala estiver inconsistente.
List<ScaleEntry> _scaleEntriesFromQuerySafe(
    QuerySnapshot<Map<String, dynamic>>? snap) {
  if (snap == null) return [];
  final out = <ScaleEntry>[];
  for (final d in snap.docs) {
    try {
      out.add(ScaleEntry.fromDoc(d));
    } catch (_) {}
  }
  return out;
}

/// True se o intervalo do filtro da seção Escalas cobre o mês civil inteiro de [ref] (para reutilizar snapshot e não abrir outro listener).
bool _dateRangeCoversFullCalendarMonth(
    DateTime rangeStart, DateTime rangeEnd, DateTime ref) {
  final m0 = DateTime(ref.year, ref.month, 1);
  final mLast = DateTime(ref.year, ref.month + 1, 0);
  final rs = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
  final re = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
  return !rs.isAfter(m0) && !re.isBefore(mLast);
}

class DashboardScreen extends StatefulWidget {
  final String uid;
  final UserProfile profile;
  final void Function(int index)? onNavigateTo;

  /// Quando dentro do [HomeShell]: scroll volta ao topo ao mudar de módulo.
  final ScrollController? shellScrollController;

  const DashboardScreen({
    super.key,
    required this.uid,
    required this.profile,
    this.onNavigateTo,
    this.shellScrollController,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  /// `users/{id}/…` alinhado a [request.auth.uid] (web/sessão).
  String get _userFsId => firestoreUserDocIdForAppShell(widget.uid);

  /// iOS: promo “limitada” oculta até mudar o ID da promo (nova campanha).
  String? _hiddenIosLimitedPromoId;

  /// Web/Android: promo no painel — checkout Mercado Pago no app.
  String? _hiddenWebAndroidPromoId;
  static bool _maintenanceExpiredCleared = false;
  String _selectedPeriod = 'Mensal';
  static const List<String> _periods = [
    'Diário',
    'Semanal',
    'Mensal',
    'Mês anterior',
    'Anual',
    'Por período'
  ];
  DateTime? _customRangeStart;
  DateTime? _customRangeEnd;

  /// Filtro só da seção Produtividade de Escalas e Por vínculo (Estado/Município). Null ou 'Geral' = usa filtro geral.
  String? _escalasSectionPeriod;
  DateTime? _escalasCustomStart;
  DateTime? _escalasCustomEnd;

  /// Filtro independente do card verde «Audiências e Compromissos em aberto» (não usa o período geral do painel).
  String _agendaCardPeriod = AgendaPeriodKeys.anual;
  DateTime? _agendaCardCustomStart;
  DateTime? _agendaCardCustomEnd;

  AgendaPeriodFilterValue get _agendaCardPeriodValue => agendaPeriodFilterValue(
        period: _agendaCardPeriod,
        customStart: _agendaCardCustomStart,
        customEnd: _agendaCardCustomEnd,
      );
  static const List<String> _escalasSectionPeriodOptions = [
    'Geral',
    'Mês anterior',
    'Mensal',
    'Semanal',
    'Anual',
    'Por período'
  ];

  /// Padrão **Anual** para o painel de Produtividade no início.
  /// O usuário pediu para começar mostrando o ano inteiro (mais informação
  /// disponível de cara) e mudar os chips só se quiser refinar.
  String _produtividadeChartPeriod = 'Anual';
  static const List<String> _produtividadePeriods = [
    'Anual',
    'Semanal',
    'Quinzenal',
    'Mensal',
    'Por período'
  ];
  DateTime? _produtividadeCustomStart;
  DateTime? _produtividadeCustomEnd;

  /// Cantos e ritmo vertical — painel Início (cartões e gráficos alinhados).
  static const double _kDashSurfaceRadius = 16;
  static const double _kDashHeroGap = 12;
  static const double _kDashBlockGap = 20;
  static const double _kDashChartTitleGap = 12;

  /// Limite inferior do campo `date` nas queries dos gráficos financeiros do painel.
  /// Transações com `date` antes disso não entram no snapshot (saldo de abertura pode subestimar nesse caso extremo).
  static final DateTime _kDashboardTxGlobalLowerCap = DateTime(1990, 1, 1);

  /// Ocultar valores na faixa financeira do Início (preferência local).
  bool _hideSensitiveBalances = false;

  /// Evita repetir `.get()` de `effectiveDate` quando só o frame reconstrói.
  int? _dashboardOpeningMemoKey;
  Future<double>? _dashboardOpeningMemoFuture;

  /// Saldo de abertura estável no painel (sem FutureBuilder a cada evento do stream).
  String _dashboardOpeningBalancePeriodKey = '';
  double? _dashboardOpeningBalanceCached;

  /// KPIs financeiros do resumo verde (servidor — evita varrer transactions no cliente).
  String _dashboardFinanceKpiKey = '';
  double? _dashboardFinanceIncomeCached;
  double? _dashboardFinanceExpenseCached;
  int _dashboardFinancePendingCountCached = 0;
  bool _dashboardFinanceKpiLoading = false;

  Timer? _agendaAutoCloseDebounce;
  final Set<String> _agendaAutoCloseInFlight = {};

  @override
  void didUpdateWidget(covariant DashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _dashboardOpeningMemoKey = null;
      _dashboardOpeningMemoFuture = null;
      _dashboardOpeningBalancePeriodKey = '';
      _dashboardOpeningBalanceCached = null;
      _dashboardFinanceKpiKey = '';
      _dashboardFinanceIncomeCached = null;
      _dashboardFinanceExpenseCached = null;
      _dashboardFinancePendingCountCached = 0;
    }
  }

  @override
  void dispose() {
    FinanceTransactionsHub.revision.removeListener(_onFinanceHubRevision);
    _agendaAutoCloseDebounce?.cancel();
    _dashboardOpeningMemoKey = null;
    _dashboardOpeningMemoFuture = null;
    super.dispose();
  }

  void _scheduleAgendaAutoCloseFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
    CollectionReference<Map<String, dynamic>> remindersRef,
  ) {
    final now = DateTime.now();
    final toClose = <String>[];
    for (final d in snap.docs) {
      if (agendaShouldAutoCloseNow(d.data(), now)) {
        toClose.add(d.id);
      }
    }
    if (toClose.isEmpty) return;
    _agendaAutoCloseDebounce?.cancel();
    _agendaAutoCloseDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      final batch = <String>[];
      for (final id in toClose) {
        if (_agendaAutoCloseInFlight.add(id)) batch.add(id);
      }
      if (batch.isEmpty) return;
      try {
        for (final id in batch) {
          await remindersRef.doc(id).update({
            'done': true,
            'status': 'REALIZADO',
          }).catchError((_) {});
        }
      } finally {
        for (final id in batch) {
          _agendaAutoCloseInFlight.remove(id);
        }
      }
    });
  }

  @override
  void initState() {
    super.initState();
    SensitiveBalancePreferences.load().then((v) {
      if (mounted) setState(() => _hideSensitiveBalances = v);
    });
    final (initRs, _) = _rangeForPeriod();
    final initLimite = DateTime(initRs.year, initRs.month, initRs.day);
    final peekOpen = FinanceOpeningBalanceService.peekCached(
      uid: widget.uid,
      periodStart: initLimite,
      loadAccounts: false,
    );
    if (peekOpen != null) {
      _dashboardOpeningBalanceCached = peekOpen.total;
      _dashboardOpeningBalancePeriodKey =
          '${initLimite.year}-${initLimite.month}-${initLimite.day}';
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final delay = defaultTargetPlatform == TargetPlatform.android
          ? const Duration(seconds: 6)
          : const Duration(milliseconds: 800);
      Future<void>.delayed(delay, () {
        if (!mounted) return;
        unawaited(RelatorioService.warmUpPdfAssets());
        unawaited(_ensureFinanceOpeningBucketsRebuildOnce());
        _ensureDashboardOpeningBalance(initLimite);
        final (rs, re) = _rangeForPeriod();
        _ensureDashboardFinanceKpis(rs, re);
      });
    });
    FinanceTransactionsHub.revision.addListener(_onFinanceHubRevision);
  }

  void _onFinanceHubRevision() {
    if (!mounted) return;
    setState(() {
      _dashboardOpeningMemoKey = null;
      _dashboardOpeningMemoFuture = null;
      _dashboardOpeningBalancePeriodKey = '';
      _dashboardOpeningBalanceCached = null;
      _dashboardFinanceKpiKey = '';
      _dashboardFinanceIncomeCached = null;
      _dashboardFinanceExpenseCached = null;
      _dashboardFinancePendingCountCached = 0;
    });
    FinanceServerTotals.invalidateForUser(_userFsId);
    final (rs, re) = _rangeForPeriod();
    _ensureDashboardFinanceKpis(rs, re);
    _ensureDashboardOpeningBalance(DateTime(rs.year, rs.month, rs.day));
  }

  /// Reconstrói agregados mensais no servidor (uma vez por sessão se ainda não migrado).
  Future<void> _ensureFinanceOpeningBucketsRebuildOnce() async {
    await FinanceOpeningBalanceService.ensureServerBucketsRebuildIfNeeded(widget.uid);
  }

  /// Fim do período para a lista "Plantões a tirar" — sempre do dia de hoje para frente.
  DateTime _endForPlantoesAFuturo() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'Diário':
        return DateTime(now.year, now.month, now.day, 23, 59, 59);
      case 'Semanal':
        return now.add(const Duration(days: 7));
      case 'Mensal':
      case 'Mês anterior':
        return DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      case 'Anual':
        return DateTime(now.year, 12, 31, 23, 59, 59);
      case 'Por período':
        return _customRangeEnd ??
            DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      default:
        return DateTime(now.year, now.month + 1, 0, 23, 59, 59);
    }
  }

  /// Retorna (início, fim) do período selecionado para escalas/transações.
  /// Fim sempre em 23:59:59 do último dia para incluir o dia inteiro (Anual, Mensal, etc.).
  (DateTime, DateTime) _rangeForPeriod() {
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    switch (_selectedPeriod) {
      case 'Diário':
        return (DateTime(now.year, now.month, now.day), endOfToday);
      case 'Semanal':
        final start = now.subtract(const Duration(days: 7));
        return (DateTime(start.year, start.month, start.day), endOfToday);
      case 'Mensal':
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 0, 23, 59, 59)
        );
      case 'Mês anterior':
        final lastMonth = DateTime(now.year, now.month - 1);
        return (
          DateTime(lastMonth.year, lastMonth.month, 1),
          DateTime(lastMonth.year, lastMonth.month + 1, 0, 23, 59, 59)
        );
      case 'Anual':
        // Ano completo (1º jan a 31 dez) para incluir despesas com data futura no ano (ex.: paga antecipada 10/03); igual critério do Por período.
        return (
          DateTime(now.year, 1, 1),
          DateTime(now.year, 12, 31, 23, 59, 59)
        );
      case 'Por período':
        final start = _customRangeStart ?? DateTime(now.year, now.month, 1);
        final end = _customRangeEnd ?? now;
        final endNorm = end.isBefore(start) ? start : end;
        return (
          DateTime(start.year, start.month, start.day),
          DateTime(endNorm.year, endNorm.month, endNorm.day, 23, 59, 59)
        );
      default:
        return (DateTime(now.year, now.month, 1), endOfToday);
    }
  }

  /// Período efetivo da seção Escalas e Por vínculo: se _escalasSectionPeriod for null/Geral usa o geral; senão usa o filtro da seção.
  (DateTime, DateTime) _rangeForEscalasSection() {
    final now = DateTime.now();
    final endOfToday = DateTime(now.year, now.month, now.day, 23, 59, 59);
    final period =
        (_escalasSectionPeriod == null || _escalasSectionPeriod == 'Geral')
            ? _selectedPeriod
            : _escalasSectionPeriod!;
    switch (period) {
      case 'Mês anterior':
        final lastMonth = DateTime(now.year, now.month - 1);
        return (
          DateTime(lastMonth.year, lastMonth.month, 1),
          DateTime(lastMonth.year, lastMonth.month + 1, 0, 23, 59, 59)
        );
      case 'Mensal':
        // Mês civil completo (até último dia 23:59), não só até hoje — senão plantões futuros no mês
        // não entram na query e "Não tirados" / gráfico ficam zerados (Por período funcionava).
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 0, 23, 59, 59)
        );
      case 'Semanal':
        final start = now.subtract(const Duration(days: 7));
        return (DateTime(start.year, start.month, start.day), endOfToday);
      case 'Anual':
        return (
          DateTime(now.year, 1, 1),
          DateTime(now.year, 12, 31, 23, 59, 59)
        );
      case 'Por período':
        final start = _escalasCustomStart ?? DateTime(now.year, now.month, 1);
        final end = _escalasCustomEnd ?? now;
        final endNorm = end.isBefore(start) ? start : end;
        return (
          DateTime(start.year, start.month, start.day),
          DateTime(endNorm.year, endNorm.month, endNorm.day, 23, 59, 59)
        );
      default:
        return _rangeForPeriod();
    }
  }

  DateTime _endForPlantoesAFuturoForEscalas() {
    final period =
        (_escalasSectionPeriod == null || _escalasSectionPeriod == 'Geral')
            ? _selectedPeriod
            : _escalasSectionPeriod!;
    final now = DateTime.now();
    switch (period) {
      case 'Mês anterior':
        return DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      case 'Mensal':
        return DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      case 'Semanal':
        return now.add(const Duration(days: 7));
      case 'Anual':
        return DateTime(now.year, 12, 31, 23, 59, 59);
      case 'Por período':
        return _escalasCustomEnd ??
            DateTime(now.year, now.month + 1, 0, 23, 59, 59);
      default:
        return _endForPlantoesAFuturo();
    }
  }

  String _escalasSectionPeriodLabel() {
    if (_escalasSectionPeriod == null || _escalasSectionPeriod == 'Geral')
      return _selectedPeriod;
    return _escalasSectionPeriod!;
  }

  /// Retorna (início, fim) do período completo para Audiências e Compromissos em aberto.
  /// Diferente de _rangeForPeriod(), cobre o período inteiro (ex.: mês todo, ano todo).
  (DateTime, DateTime) _rangeForAgendaPeriod() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'Diário':
        final start = DateTime(now.year, now.month, now.day);
        return (start, DateTime(now.year, now.month, now.day, 23, 59, 59));
      case 'Semanal':
        final start = now.subtract(const Duration(days: 7));
        final startDay = DateTime(start.year, start.month, start.day);
        return (startDay, DateTime(now.year, now.month, now.day, 23, 59, 59));
      case 'Mensal':
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
        return (start, end);
      case 'Mês anterior':
        final lastMonth = DateTime(now.year, now.month - 1);
        return (
          DateTime(lastMonth.year, lastMonth.month, 1),
          DateTime(lastMonth.year, lastMonth.month + 1, 0, 23, 59, 59)
        );
      case 'Anual':
        return (
          DateTime(now.year, 1, 1),
          DateTime(now.year, 12, 31, 23, 59, 59)
        );
      case 'Por período':
        final start = _customRangeStart ?? DateTime(now.year, now.month, 1);
        final end = _customRangeEnd ?? now;
        final endDay = end.isBefore(start) ? start : end;
        return (
          DateTime(start.year, start.month, start.day),
          DateTime(endDay.year, endDay.month, endDay.day, 23, 59, 59)
        );
      default:
        final start = DateTime(now.year, now.month, 1);
        return (start, DateTime(now.year, now.month + 1, 0, 23, 59, 59));
    }
  }

  /// Para o gráfico de barras: últimos N intervalos (ex.: 3 meses ou 4 semanas).
  List<(DateTime, DateTime)> _rangesForChart() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'Semanal':
        return List.generate(4, (i) {
          final end = now.subtract(Duration(days: i * 7));
          final start = end.subtract(const Duration(days: 7));
          return (start, end);
        }).reversed.toList();
      case 'Mensal':
        return List.generate(3, (i) {
          final m = now.month - 2 + i;
          final y = now.year + (m <= 0 ? -1 : 0);
          final month = m <= 0 ? m + 12 : m;
          return (DateTime(y, month, 1), DateTime(y, month + 1, 0));
        });
      case 'Mês anterior':
        final lastMonth = DateTime(now.year, now.month - 1);
        return [
          (
            DateTime(lastMonth.year, lastMonth.month, 1),
            DateTime(lastMonth.year, lastMonth.month + 1, 0)
          )
        ];
      case 'Anual':
        return List.generate(6, (i) {
          final m = now.month - 5 + i;
          final y = now.year + (m <= 0 ? -1 : 0);
          final month = m <= 0 ? m + 12 : m;
          return (DateTime(y, month, 1), DateTime(y, month + 1, 0));
        });
      case 'Por período':
        final start = _customRangeStart ?? DateTime(now.year, now.month, 1);
        final end = _customRangeEnd ?? now;
        final endNorm = end.isBefore(start) ? start : end;
        return [
          (
            DateTime(start.year, start.month, start.day),
            DateTime(endNorm.year, endNorm.month, endNorm.day, 23, 59, 59)
          )
        ];
      default:
        return List.generate(7, (i) {
          final d = now.subtract(Duration(days: 6 - i));
          return (DateTime(d.year, d.month, d.day), d);
        });
    }
  }

  /// Rótulo dinâmico do card «Folgas …» baseado no chip de período do
  /// painel de Produtividade. Antes era fixo «Folgas no ano» mesmo quando o
  /// filtro era Mensal/Semanal, o que enganava o usuário.
  String _folgasCardLabel() {
    switch (_produtividadeChartPeriod) {
      case 'Semanal':
        return 'Folgas (semanas)';
      case 'Quinzenal':
        return 'Folgas (quinzenas)';
      case 'Mensal':
        return 'Folgas no período';
      case 'Anual':
        return 'Folgas no ano';
      case 'Por período':
        return 'Folgas no período';
      default:
        return 'Folgas no período';
    }
  }

  /// Intervalos para o gráfico de produtividade/ocorrências (Anual / Semanal / Quinzenal / Mensal / Por período).
  List<(DateTime, DateTime)> _produtividadeRanges() {
    final now = DateTime.now();
    switch (_produtividadeChartPeriod) {
      case 'Semanal':
        return List.generate(4, (i) {
          final end = now.subtract(Duration(days: i * 7));
          final start = end.subtract(const Duration(days: 7));
          return (
            DateTime(start.year, start.month, start.day),
            DateTime(end.year, end.month, end.day, 23, 59, 59)
          );
        }).reversed.toList();
      case 'Quinzenal':
        return List.generate(4, (i) {
          final end = now.subtract(Duration(days: (3 - i) * 15));
          final start = end.subtract(const Duration(days: 15));
          return (
            DateTime(start.year, start.month, start.day),
            DateTime(end.year, end.month, end.day, 23, 59, 59)
          );
        });
      case 'Mensal':
        return List.generate(6, (i) {
          final m = now.month - 5 + i;
          final y = now.year + (m <= 0 ? -1 : 0);
          final month = m <= 0 ? m + 12 : m;
          return (DateTime(y, month, 1), DateTime(y, month + 1, 0, 23, 59, 59));
        });
      case 'Anual':
        return List.generate(12, (i) {
          final month = i + 1;
          return (
            DateTime(now.year, month, 1),
            DateTime(now.year, month + 1, 0, 23, 59, 59)
          );
        });
      case 'Por período':
        final start =
            _produtividadeCustomStart ?? DateTime(now.year, now.month, 1);
        final end = _produtividadeCustomEnd ?? now;
        final endNorm = end.isBefore(start) ? start : end;
        return [
          (
            DateTime(start.year, start.month, start.day),
            DateTime(endNorm.year, endNorm.month, endNorm.day, 23, 59, 59)
          )
        ];
      default:
        return List.generate(6, (i) {
          final m = now.month - 5 + i;
          final y = now.year + (m <= 0 ? -1 : 0);
          final month = m <= 0 ? m + 12 : m;
          return (DateTime(y, month, 1), DateTime(y, month + 1, 0, 23, 59, 59));
        });
    }
  }

  /// Registra aporte na meta sem sair da tela (mesmo fluxo do módulo Meta Financeira).
  Future<void> _registrarAporte(BuildContext context,
      DocumentReference<Map<String, dynamic>> goalRef) async {
    final ok = await showRegistrarAporteDialog(
      context: context,
      goalRef: goalRef,
      profile: widget.profile,
    );
    if (ok && mounted && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Aporte registrado!')));
    }
  }

  Future<void> _lancamentoRapido(BuildContext context, String type) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final result = await Navigator.of(context, rootNavigator: true).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => NovoLancamentoPage(
          uid: _userFsId,
          initialType: type,
          canAttachReceipt: widget.profile.temAcessoPremium,
          hasActiveLicense: widget.profile.hasActiveLicense,
        ),
        fullscreenDialog: true,
      ),
    );
    if (result == null || !mounted) return;
    try {
      final saveResult = await TransactionSaveService.saveFromNovoLancamentoResult(
        uid: _userFsId,
        data: result,
        context: context,
      );
      if (saveResult == null || !mounted) return;
      final (rs, _) = _rangeForPeriod();
      final limite = DateTime(rs.year, rs.month, rs.day);
      FinanceOpeningBalanceService.invalidateForUser(widget.uid);
      setState(() {
        _dashboardOpeningMemoKey = null;
        _dashboardOpeningMemoFuture = null;
        _dashboardOpeningBalancePeriodKey = '';
        _dashboardOpeningBalanceCached = null;
      });
      _ensureDashboardOpeningBalance(limite);
    } catch (e, st) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Erro ao salvar lançamento: ${e.toString().replaceFirst(RegExp(r'^Exception:?\s*'), '')}'),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
      debugPrint('_lancamentoRapido save error: $e\n$st');
    }
  }

  /// Botão premium com gradiente vivo, ícone em pill branca translúcida e sombra colorida 3D.
  /// Usado nos atalhos de Lançamento expresso (financeiro / escala) do painel inicial.
  Widget _premiumGradientButton({
    required String label,
    String? sublabel,
    required IconData icon,
    required List<Color> gradient,
    required VoidCallback onTap,
    bool stacked = false,
  }) {
    final base = gradient.last;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: base.withValues(alpha: 0.40),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          splashColor: Colors.white.withValues(alpha: 0.18),
          highlightColor: Colors.white.withValues(alpha: 0.08),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: 12,
              vertical: stacked ? 10 : 14,
            ),
            child: stacked
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(11),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                        child: Icon(icon, color: Colors.white, size: 20),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        label,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          fontSize: 12.5,
                          letterSpacing: 0.1,
                          shadows: [
                            Shadow(
                              color: Color(0x55000000),
                              blurRadius: 2,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                      if (sublabel != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          sublabel,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.92),
                            fontWeight: FontWeight.w600,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.35),
                            width: 1,
                          ),
                        ),
                        child: Icon(icon, color: Colors.white, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            letterSpacing: 0.1,
                            shadows: [
                              Shadow(
                                color: Color(0x55000000),
                                blurRadius: 2,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Lançamento a partir de SMS/copia: mesma tela usada no Financeiro; saldos via Stream + [setState].
  Future<void> _abrirLancamentoExpressoSms() async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (firestoreUserDocIdStrictFromSession().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Sessão a carregar — aguarde um instante e toque de novo.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final result = await Navigator.of(context).push<SmartInputPopResult?>(
      MaterialPageRoute<SmartInputPopResult?>(
        builder: (_) =>
            SmartInputScreen(uid: _userFsId, profile: widget.profile),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) return;
    if (result != null && result.hasCreated) {
      if (!context.mounted) return;
      setState(() {});
      final n = result.createdTransactionIds.length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              n > 1 ? '$n lançamentos guardados.' : 'Lançamento guardado.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 6),
          action: SnackBarAction(
            label: 'Desfazer',
            onPressed: () async {
              await FinanceService.deleteTransactionsByDocumentIds(
                uid: _userFsId,
                context: context,
                documentIds: result.createdTransactionIds,
              );
              if (context.mounted) setState(() {});
            },
          ),
        ),
      );
    }
  }

  Widget _buildAtalhoLancamentoRapido(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final twoCol = c.maxWidth >= 360;
        return Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                AppColors.primary.withValues(alpha: 0.05),
                const Color(0xFF0D9488).withValues(alpha: 0.04),
              ],
            ),
            border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.14), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepBlue.withValues(alpha: 0.1),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            colors: [
                              AppColors.primary,
                              AppColors.primary.withValues(alpha: 0.78)
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.35),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(Icons.flash_on_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Lançamento expresso',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                                color: Colors.grey.shade900,
                                letterSpacing: -0.2,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Receita, despesa ou colar linha de SMS do banco',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (twoCol)
                    Row(
                      children: [
                        Expanded(
                          child: _premiumGradientButton(
                            label: 'Receita',
                            icon: Icons.trending_up_rounded,
                            gradient: const [
                              Color(0xFF10B981),
                              Color(0xFF059669)
                            ],
                            onTap: () => _lancamentoRapido(context, 'income'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _premiumGradientButton(
                            label: 'Despesa',
                            icon: Icons.trending_down_rounded,
                            gradient: const [
                              Color(0xFFF43F5E),
                              Color(0xFFDC2626)
                            ],
                            onTap: () => _lancamentoRapido(context, 'expense'),
                          ),
                        ),
                      ],
                    )
                  else ...[
                    _premiumGradientButton(
                      label: 'Receita',
                      icon: Icons.trending_up_rounded,
                      gradient: const [Color(0xFF10B981), Color(0xFF059669)],
                      onTap: () => _lancamentoRapido(context, 'income'),
                    ),
                    const SizedBox(height: 8),
                    _premiumGradientButton(
                      label: 'Despesa',
                      icon: Icons.trending_down_rounded,
                      gradient: const [Color(0xFFF43F5E), Color(0xFFDC2626)],
                      onTap: () => _lancamentoRapido(context, 'expense'),
                    ),
                  ],
                  const SizedBox(height: 10),
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: widget.profile.hasActiveLicense
                          ? _abrirLancamentoExpressoSms
                          : () => mostrarAvisoSeLicencaInativa(
                              context, widget.profile),
                      borderRadius: BorderRadius.circular(16),
                      child: Ink(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: const LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            colors: [
                              AppColors.deepBlueDark,
                              AppColors.deepBlue,
                              AppColors.primary,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.primary.withValues(alpha: 0.45),
                              blurRadius: 18,
                              offset: const Offset(0, 7),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.10),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              vertical: 14, horizontal: 12),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.20),
                                  borderRadius: BorderRadius.circular(11),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.35),
                                    width: 1,
                                  ),
                                ),
                                child: const Icon(Icons.sms_rounded,
                                    size: 20, color: Colors.white),
                              ),
                              const SizedBox(width: 10),
                              const Flexible(
                                child: Text(
                                  'Lançamento por mensagem (SMS / banco)',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.5,
                                    height: 1.2,
                                    letterSpacing: 0.1,
                                    shadows: [
                                      Shadow(
                                        color: Color(0x55000000),
                                        blurRadius: 2,
                                        offset: Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                  maxLines: 2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          Icons.lightbulb_outline_rounded,
                          size: 16,
                          color: AppColors.accent.withValues(alpha: 0.9),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text.rich(
                          const TextSpan(
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                            children: [
                              TextSpan(
                                text:
                                    'Copie a mensagem do banco, volte ao app, toque no botão acima (cores da marca) e use ',
                              ),
                              TextSpan(
                                text: 'Colar',
                                style: TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              TextSpan(
                                text:
                                    ' — o app monta valor, data e descrição no aparelho; depois confirme para salvar.',
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Atalho no painel: mesmo fluxo do módulo Escalas (lançamento expresso), sem navegar para Escalas.
  Future<void> _lancamentoEscalaExpressoPainel(BuildContext context,
      {required bool comFinanceiro}) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final hoje =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    await showLancamentoExpressoPlantaoSheet(
      context: context,
      uid: _userFsId,
      day: hoje,
      initialFinanceiro: comFinanceiro,
      initialEmployer: EmployerType.state,
      onSalvar: () {
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildAtalhoLancamentoEscalaExpresso(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.09),
            const Color(0xFF0D47A1).withValues(alpha: 0.07),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
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
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(Icons.event_available_rounded,
                    size: 22, color: AppColors.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Escala / compromisso rápido',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: Colors.grey.shade900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Sem abrir Escalas · aparece no calendário e nos relatórios',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade600,
                          height: 1.25),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _premiumGradientButton(
                  label: 'Plantão expresso',
                  sublabel: 'Com valor financeiro',
                  icon: Icons.bolt_rounded,
                  gradient: const [Color(0xFFFB923C), Color(0xFFF97316)],
                  onTap: () => _lancamentoEscalaExpressoPainel(context,
                      comFinanceiro: true),
                  stacked: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _premiumGradientButton(
                  label: 'Compromisso particular',
                  sublabel: 'Sem valor financeiro',
                  icon: Icons.event_available_rounded,
                  gradient: const [Color(0xFF14B8A6), Color(0xFF0D9488)],
                  onTap: () => _lancamentoEscalaExpressoPainel(context,
                      comFinanceiro: false),
                  stacked: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Atalho premium: **Dicas · Orçamentos domésticos** — mesmo fluxo que Links em Minhas Anotações (navegador).
  Widget _buildDicasOrcamentosDomesticosPremiumCard(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    final compactCta = w < 380;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          HapticFeedback.lightImpact();
          try {
            await openUrlPreferChrome(_kDicasBoraInvestirUrl);
          } catch (e) {
            debugPrint('[Dicas Bora Investir] abrir link: $e');
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Não foi possível abrir o link. Verifique a conexão e tente de novo.'),
                backgroundColor: AppColors.error,
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
            gradient: const LinearGradient(
              colors: [
                Color(0xFF0F2942),
                Color(0xFF1A4A66),
                Color(0xFF0D6B63),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              stops: [0.0, 0.42, 1.0],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0A1E33).withValues(alpha: 0.5),
                blurRadius: 26,
                offset: const Offset(0, 14),
                spreadRadius: -4,
              ),
              BoxShadow(
                color: AppColors.accent.withValues(alpha: 0.28),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            clipBehavior: Clip.antiAlias,
            children: [
              Positioned(
                right: -36,
                top: -44,
                child: IgnorePointer(
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.06),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: -28,
                bottom: -36,
                child: IgnorePointer(
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withValues(alpha: 0.14),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                top: 1,
                child: IgnorePointer(
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          const Color(0xFFE8DCC8).withValues(alpha: 0.55),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 14, 18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withValues(alpha: 0.32),
                            Colors.white.withValues(alpha: 0.08),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.38)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          Icon(
                            Icons.home_work_rounded,
                            color: Colors.white.withValues(alpha: 0.96),
                            size: 26,
                          ),
                          Positioned(
                            right: 6,
                            top: 6,
                            child: Icon(
                              Icons.auto_awesome_rounded,
                              color: const Color(0xFFFFE8C8)
                                  .withValues(alpha: 0.95),
                              size: 15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dicas · Orçamentos domésticos',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16.5,
                              letterSpacing: -0.45,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Toque para abrir no navegador — como os links em Minhas Anotações.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.88),
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.28,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (!compactCta)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 9),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.34)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'Abrir',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.98),
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              Icons.arrow_forward_rounded,
                              color: Colors.white.withValues(alpha: 0.95),
                              size: 18,
                            ),
                          ],
                        ),
                      )
                    else
                      Icon(
                        Icons.arrow_circle_right_rounded,
                        color: Colors.white.withValues(alpha: 0.92),
                        size: 34,
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (rangeStart, rangeEnd) = _rangeForPeriod();
    final (escalasStart, escalasEnd) = _rangeForEscalasSection();
    final escalasEndFirestoreExclusive =
        _firestoreExclusiveEndAfterLastDay(escalasEnd);
    final agendaPeriodCard = _agendaCardPeriodValue;
    final agendaStart = agendaPeriodCard.rangeStart;
    final agendaEnd = agendaPeriodCard.rangeEnd;
    final hoje =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final endPlantoesEscalas = _endForPlantoesAFuturoForEscalas();
    final escalasPeriodLabel = _escalasSectionPeriodLabel();
    final isNarrow = MediaQuery.sizeOf(context).width < 720;
    final embeddedInShell = widget.shellScrollController != null;

    return Container(
      color: const Color(0xFFF4F7FA),
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // SingleChildScrollView: se a tela for pequena para o conteúdo na vertical, habilita scroll em vez de overflow (faixas amarelas/pretas).
            return SingleChildScrollView(
              controller: widget.shellScrollController,
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                isNarrow ? 16 : 20,
                0,
                isNarrow ? 16 : 20,
                embeddedInShell ? 8 : (isNarrow ? 16 : 20),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildNovaVersaoPainelBanner(),
                    SizedBox(height: _kDashHeroGap),
                    _buildManutencaoBanner(),
                    SizedBox(height: _kDashHeroGap),
                    _buildIosLimitedPromoBanner(),
                    SizedBox(height: _kDashHeroGap),
                    _buildWebAndroidPromoBanner(),
                    SizedBox(height: _kDashHeroGap),
                    // Ordem do painel inicial (pedido do usuário):
                    // 1) Audiências/Compromissos em aberto
                    // 2) Lançamento expresso (Escala + Compromisso)
                    // 3) Controle de horas (já tirou / previsão / teto / passou ou não)
                    // 4) Lançamento expresso financeiro
                    // Depois segue o restante normal (selector de período, pendências, etc.).
                    _buildAgendaResumo(agendaStart, agendaEnd),
                    SizedBox(height: _kDashHeroGap),
                    _buildAtalhoLancamentoEscalaExpresso(context),
                    SizedBox(height: _kDashHeroGap),
                    _buildFaixaAvisoTeto192(
                      context,
                      hoje,
                      endPlantoesEscalas,
                      hoje,
                      forPainelTopo: true,
                    ),
                    SizedBox(height: _kDashHeroGap),
                    _buildAtalhoLancamentoRapido(context),
                    SizedBox(height: _kDashHeroGap),
                    if (kIsWeb && !isPwaStandalone)
                      const InstallPwaCard(visible: true),
                    if (kIsWeb && !isPwaStandalone)
                      SizedBox(height: _kDashBlockGap),
                    _buildPeriodSelector(),
                    SizedBox(height: _kDashBlockGap),
                    _buildReceitasPendentesBand(context),
                    SizedBox(height: _kDashHeroGap),
                    _buildDespesasPendentesBand(context),
                    SizedBox(height: _kDashHeroGap),
                    _buildFaturaEmAbertoBand(context),
                    SizedBox(height: _kDashHeroGap),
                    _buildVenceHojeBanner(),
                    SizedBox(height: _kDashHeroGap),
                    _buildDicasOrcamentosDomesticosPremiumCard(context),
                    SizedBox(height: _kDashHeroGap),
                    _buildBlueSummaryBand(
                        rangeStart, rangeEnd, _selectedPeriod),
                    SizedBox(height: _kDashBlockGap),
                    _buildSectionTitle('Fluxo de Caixa'),
                    SizedBox(height: _kDashChartTitleGap),
                    _buildMergedFinanceChartsBlock(rangeStart, rangeEnd),
                    SizedBox(height: _kDashBlockGap),
                    _buildSectionTitle('Progresso de Metas'),
                    SizedBox(height: _kDashChartTitleGap),
                    _buildGoalProgress(),
                    SizedBox(height: _kDashBlockGap),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onNavigateTo?.call(3),
                      child: _buildSectionTitle('Produtividade de Escalas'),
                    ),
                    const SizedBox(height: 6),
                    if (widget.onNavigateTo != null)
                      Text('Toque para abrir Escalas',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    SizedBox(height: _kDashHeroGap),
                    _buildEscalasSectionPeriodSelector(),
                    SizedBox(height: _kDashChartTitleGap),
                    StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: FirebaseFirestore.instance
                          .collection('users')
                          .doc(_userFsId)
                          .collection('scales')
                          .where('date',
                              isGreaterThanOrEqualTo: Timestamp.fromDate(
                                  _dateOnlyLocalDash(escalasStart)))
                          .where('date',
                              isLessThan: Timestamp.fromDate(
                                  escalasEndFirestoreExclusive))
                          .snapshots(),
                      builder: (context, snap) {
                        final entries = _scaleEntriesFromQuerySafe(snap.data);
                        final periodLabel = _periodLabel(
                            escalasStart, escalasEnd, escalasPeriodLabel);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildEscalaStats(entries, periodLabel),
                            SizedBox(height: _kDashChartTitleGap),
                            _buildEscalaChart(entries),
                            SizedBox(height: _kDashHeroGap),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 10),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius:
                                    BorderRadius.circular(_kDashSurfaceRadius),
                                border:
                                    Border.all(color: Colors.amber.shade200),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline_rounded,
                                      size: 16, color: Colors.amber.shade800),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Banco de Horas: 05h às 22h (diurno); 22h01 às 05h (noturno). Padrão GO: até 23:59 no dia; 00h às 07h (próx. dia) no mês seguinte.',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.amber.shade900),
                                      softWrap: true,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            SizedBox(height: _kDashBlockGap),
                            _buildSectionTitle(
                                'Por vínculo (Estado / Município / Particular)'),
                            const SizedBox(height: 8),
                            Text(
                                'Usa o mesmo filtro de período da seção Produtividade de Escalas acima.',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                            SizedBox(height: _kDashHeroGap),
                            StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                              stream: FirebaseFirestore.instance
                                  .collection('users')
                                  .doc(_userFsId)
                                  .collection('locations')
                                  .snapshots(),
                              builder: (context, locSnap) {
                                final locations = (locSnap.data?.docs ?? [])
                                    .map((d) =>
                                        ShiftLocation.fromMap(d.id, d.data()))
                                    .where((l) =>
                                        l.name.isNotEmpty ||
                                        l.abbreviation.isNotEmpty)
                                    .toList();
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    _buildQuadrosEstadoMunicipioParticular(
                                        entries, hoje, periodLabel, locations),
                                    const SizedBox(height: 16),
                                    ScaleMonthClosureInviteCard(
                                      uid: firestoreUserDocIdForAppShell(
                                          widget.uid),
                                      profile: widget.profile,
                                      entriesSource: entries,
                                      locations: locations,
                                      periodStart:
                                          _dateOnlyLocalDash(escalasStart),
                                      periodEnd: _dateOnlyLocalDash(escalasEnd),
                                      periodLabel: periodLabel,
                                      allowEditPeriodFromSource: false,
                                    ),
                                    const SizedBox(height: 20),
                                    _buildEarningsCard(
                                        entries, hoje, periodLabel, locations),
                                  ],
                                );
                              },
                            ),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 30),
                    _buildProdutividadeSection(),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// Seletor de período só para Produtividade de Escalas e Por vínculo (Estado/Município). Geral = usa filtro do topo.
  Widget _buildEscalasSectionPeriodSelector() {
    final now = DateTime.now();
    final effective = _escalasSectionPeriod ?? 'Geral';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A237E).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFF1A237E).withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filtro desta seção (Escalas + Por vínculo)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade700)),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (ctx, c) => _dashChipRowScrollOrWrap(
              maxWidth: c.maxWidth,
              wideThreshold: 580,
              spacing: 8,
              runSpacing: 8,
              chips: _escalasSectionPeriodOptions
                  .map((p) => ChoiceChip(
                        label: Text(p,
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: effective == p
                                    ? Colors.white
                                    : const Color(0xFF1A237E))),
                        selected: effective == p,
                        onSelected: (_) {
                          setState(() {
                            _escalasSectionPeriod = p == 'Geral' ? null : p;
                            if (p == 'Por período') {
                              _escalasCustomStart ??=
                                  DateTime(now.year, now.month, 1);
                              _escalasCustomEnd ??= now;
                            }
                          });
                        },
                        selectedColor: const Color(0xFF1A237E),
                        backgroundColor: Colors.white,
                        side: BorderSide(
                            color: effective == p
                                ? const Color(0xFF1A237E)
                                : Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                      ))
                  .toList(),
            ),
          ),
          if (effective == 'Por período') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                          context: context,
                          initialDate: _escalasCustomStart ??
                              DateTime(now.year, now.month, 1),
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2030));
                      if (picked != null && mounted)
                        setState(() => _escalasCustomStart = picked);
                    },
                    icon: const Icon(Icons.calendar_today_rounded, size: 18),
                    label: Text(
                        'Início: ${DateFormat('dd/MM/yyyy', 'pt_BR').format(_escalasCustomStart ?? DateTime(now.year, now.month, 1))}',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                          context: context,
                          initialDate: _escalasCustomEnd ?? now,
                          firstDate: _escalasCustomStart ?? DateTime(2000),
                          lastDate: DateTime(2030));
                      if (picked != null && mounted)
                        setState(() => _escalasCustomEnd = picked);
                    },
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text(
                        'Fim: ${DateFormat('dd/MM/yyyy', 'pt_BR').format(_escalasCustomEnd ?? now)}',
                        style: const TextStyle(fontSize: 12)),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Limpa os campos de manutenção no Firestore quando a data já passou (no dia posterior). Executado apenas uma vez por sessão.
  static void _clearExpiredMaintenanceOnce() {
    if (_maintenanceExpiredCleared) return;
    _maintenanceExpiredCleared = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FirebaseFirestore.instance.doc('system/config').set({
        'maintenanceMessage': '',
        'maintenanceDate': '',
        'maintenanceTime': '',
        'maintenancePromoUrl': '',
        'maintenancePromoUrlAndroid': '',
        'maintenancePromoUrlIos': '',
        'maintenancePromoLabel': '',
        'maintenancePromoUseOfficialSite': false,
        'maintenancePromoFirestoreId': '',
        'maintenanceTargetUids': [],
      }, SetOptions(merge: true));
    });
  }

  /// Aviso compacto no painel Início (faixa flutuante global cobre o restante do app).
  Widget _buildNovaVersaoPainelBanner() {
    return ValueListenableBuilder<bool>(
      valueListenable: VersionCheckService.forceUpdateNotifier,
      builder: (context, _, __) {
        final v = VersionCheckService.pendingUpdateVersion;
        if (v == null) return const SizedBox.shrink();
        final isIosMobile =
            !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
        final sub = kIsWeb
            ? 'Servidor $v · recarregue para aplicar'
            : isIosMobile
                ? 'Build $v · TestFlight'
                : 'Build $v · Play Store';

        return Material(
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
          child: InkWell(
            onTap: () => launchControleTotalAppUpdate(context),
            borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
            child: Ink(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
                gradient: LinearGradient(
                  colors: [
                    AppColors.deepBlueDark,
                    AppColors.deepBlue,
                    AppColors.accent.withValues(alpha: 0.92),
                  ],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      kIsWeb
                          ? Icons.auto_awesome_rounded
                          : Icons.system_update_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Atualização disponível',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 0.15,
                            ),
                          ),
                          Text(
                            '$sub · ${AppVersion.internalLabel}',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        VersionCheckService.clearPendingUpdate();
                        if (mounted) setState(() {});
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('OK',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 4),
                    FilledButton.tonal(
                      onPressed: () => launchControleTotalAppUpdate(context),
                      style: FilledButton.styleFrom(
                        foregroundColor: AppColors.deepBlueDark,
                        backgroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        kIsWeb
                            ? 'Atualizar'
                            : isIosMobile
                                ? 'TestFlight'
                                : 'Play Store',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 12),
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

  /// Safari no iPhone/iPad (site web): mensagem + link do site (checkout MP limitado no Safari).
  /// Some sozinho quando a promo acaba (mesma regra da divulgação web).
  Widget _buildIosLimitedPromoBanner() {
    if (!(kIsWeb && isPwaIos)) return const SizedBox.shrink();
    return StreamBuilder<PublicDivulgacaoPromo?>(
      stream: PublicDivulgacaoPromo.watchFeatured(),
      builder: (context, snap) {
        final promo = snap.data;
        if (promo == null) {
          if (_hiddenIosLimitedPromoId != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _hiddenIosLimitedPromoId = null);
            });
          }
          return const SizedBox.shrink();
        }
        if (_hiddenIosLimitedPromoId == promo.id)
          return const SizedBox.shrink();

        final url = buildMaintenancePromoSiteUrl(
          promoFirestoreId: promo.id,
          source: 'ios_app_limited_promo',
        );
        final baseStyle = TextStyle(
          fontSize: 14,
          color: Colors.deepPurple.shade900,
          fontWeight: FontWeight.w600,
          height: 1.35,
        );
        final linkStyle = TextStyle(
          fontSize: 14,
          color: Colors.indigo.shade700,
          fontWeight: FontWeight.w700,
          decoration: TextDecoration.underline,
          height: 1.35,
        );

        Future<void> openSite() async {
          try {
            await openPromoMaintenanceLink(url);
          } catch (_) {
            if (!context.mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Abra wisdomapp-b9e98.web.app no Safari.',
                ),
              ),
            );
          }
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.deepPurple.shade50,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.deepPurple.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  color: Colors.deepPurple.shade700, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Promoção limitada — abra o site oficial para ver os detalhes.',
                      style: baseStyle,
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => openSite(),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child:
                            Text('wisdomapp-b9e98.web.app', style: linkStyle),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () =>
                            setState(() => _hiddenIosLimitedPromoId = promo.id),
                        child: const Text('OK'),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Web (exceto Safari iPhone/iPad), Android e app iOS nativo: checkout Mercado Pago no app.
  Widget _buildWebAndroidPromoBanner() {
    if (kIsWeb && isPwaIos) return const SizedBox.shrink();
    return StreamBuilder<PublicDivulgacaoPromo?>(
      stream: PublicDivulgacaoPromo.watchFeatured(),
      builder: (context, snap) {
        final promo = snap.data;
        if (promo == null) {
          if (_hiddenWebAndroidPromoId != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _hiddenWebAndroidPromoId = null);
            });
          }
          return const SizedBox.shrink();
        }
        if (_hiddenWebAndroidPromoId == promo.id)
          return const SizedBox.shrink();

        final isAndroidNative =
            !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
        if (isAndroidNative) {
          return _buildAndroidPromoModernBanner(context, promo);
        }
        return _buildWebPromoCheckoutBanner(context, promo);
      },
    );
  }

  /// Android nativo: cartão com gradiente e CTA Mercado Pago.
  Widget _buildAndroidPromoModernBanner(
      BuildContext context, PublicDivulgacaoPromo promo) {
    return Material(
      elevation: 6,
      shadowColor: AppColors.deepBlue.withValues(alpha: 0.35),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF0B1F4B), Color(0xFF122B6B), Color(0xFF0D9488)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.25),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.amber.withValues(alpha: 0.95),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      'OFERTA',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                        color: Color(0xFF0B1F4B),
                      ),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.bolt_rounded,
                      color: AppColors.amber.withValues(alpha: 0.9), size: 26),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                promo.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.2,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${promo.priceLabel} · +${promo.durationDays} dias após pagamento aprovado',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.92),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Mercado Pago: PIX ou cartão, direto no app.',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.white.withValues(alpha: 0.78),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton.icon(
                  onPressed: () =>
                      openPublicPromoMercadoPagoCheckout(context, promo),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.deepBlueDark,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.payment_rounded, size: 22),
                  label: const Text(
                    'Pagar agora',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () =>
                      setState(() => _hiddenWebAndroidPromoId = promo.id),
                  child: Text(
                    'Ocultar',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Web (Chrome, etc.): faixa compacta com link para checkout.
  Widget _buildWebPromoCheckoutBanner(
      BuildContext context, PublicDivulgacaoPromo promo) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.local_offer_rounded,
              color: Colors.green.shade800, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Promoção limitada',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.green.shade900,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  promo.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade900,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${promo.priceLabel} · +${promo.durationDays} dias após pagamento aprovado (Mercado Pago).',
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade800, height: 1.35),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () =>
                        openPublicPromoMercadoPagoCheckout(context, promo),
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF1B5E20)),
                    child: const Text(
                      'Pagar com PIX ou cartão — abrir checkout',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          decoration: TextDecoration.underline),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () =>
                        setState(() => _hiddenWebAndroidPromoId = promo.id),
                    child: const Text('OK'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Banner de manutenção programada — aparece na tela principal até o dia da manutenção; no dia seguinte some e os dados são limpos automaticamente.
  /// O mesmo fingerprint de [PremiumGlobalMessageHost]: OK no cartão ou no diálogo central oculta ambos até nova campanha.
  Widget _buildManutencaoBanner() {
    return ValueListenableBuilder<int>(
      valueListenable: maintenanceDismissSync,
      builder: (context, _, __) {
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance.doc('system/config').snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data();
            if (data == null) return const SizedBox.shrink();
            if (!_maintenanceBannerAppliesToUid(data, _userFsId)) {
              return const SizedBox.shrink();
            }
            final fp = fingerprintForMaintenanceConfig(data);
            final msg = (data['maintenanceMessage'] ?? '').toString().trim();
            final dateStr = (data['maintenanceDate'] ?? '').toString();
            final timeStr = (data['maintenanceTime'] ?? '').toString();
            final appUpdateLinks = resolveMaintenanceAppUpdateLinks(data);
            final promoUrlRawAndroid =
                (data['maintenancePromoUrlAndroid'] ?? '').toString().trim();
            final promoUrlRawIos =
                (data['maintenancePromoUrlIos'] ?? '').toString().trim();
            final promoUrlLegacy =
                (data['maintenancePromoUrl'] ?? '').toString().trim();
            final promoFirestoreId =
                (data['maintenancePromoFirestoreId'] ?? '').toString().trim();
            final promoLabel =
                (data['maintenancePromoLabel'] ?? '').toString().trim();
            final useOfficialPromoSite =
                data['maintenancePromoUseOfficialSite'] == true;
            final effectivePromoUrlAndroid = resolveMaintenancePromoLaunchUrl(
              useOfficialPromoSite: useOfficialPromoSite,
              customUrl: promoUrlRawAndroid.isNotEmpty
                  ? promoUrlRawAndroid
                  : promoUrlLegacy,
              promoFirestoreId: promoFirestoreId,
            );
            final effectivePromoUrlIos = resolveMaintenancePromoLaunchUrl(
              useOfficialPromoSite: useOfficialPromoSite,
              customUrl: promoUrlRawIos,
              promoFirestoreId: promoFirestoreId,
            );
            final showPromoButtonAndroid = !appUpdateLinks.hasAnyButton &&
                effectivePromoUrlAndroid.isNotEmpty &&
                showAndroidStoreUi;
            final showPromoButtonIos = !appUpdateLinks.hasAnyButton &&
                effectivePromoUrlIos.isNotEmpty &&
                showIosStoreUi;
            final showPromoButton = appUpdateLinks.hasAnyButton ||
                showPromoButtonAndroid ||
                showPromoButtonIos;
            if (msg.isEmpty &&
                (dateStr.isEmpty || timeStr.isEmpty) &&
                !showPromoButton) {
              return const SizedBox.shrink();
            }
            // Validade: só exibir no dia da manutenção ou antes; no dia posterior some.
            if (dateStr.isNotEmpty) {
              final parts = dateStr.split('-');
              if (parts.length == 3) {
                final y = int.tryParse(parts[0]) ?? 0;
                final m = int.tryParse(parts[1]) ?? 0;
                final d = int.tryParse(parts[2]) ?? 0;
                if (y > 0 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
                  final maintenanceDate = DateTime(y, m, d);
                  final today = DateTime.now();
                  final todayDate =
                      DateTime(today.year, today.month, today.day);
                  if (todayDate.isAfter(maintenanceDate)) {
                    _clearExpiredMaintenanceOnce();
                    return const SizedBox.shrink();
                  }
                }
              }
            }
            String texto = msg.isNotEmpty
                ? msg
                : (appUpdateLinks.hasAnyButton
                    ? kMaintenanceImprovementsMessageDefault
                    : (showPromoButton
                        ? 'Acesse o site oficial pelo botão abaixo para ver a promoção, entrar com Google ou criar conta e concluir o pagamento.'
                        : 'Manutenção programada.'));
            if (dateStr.isNotEmpty && timeStr.isNotEmpty) {
              final parts = dateStr.split('-');
              if (parts.length == 3) {
                final d = int.tryParse(parts[2]) ?? 0;
                final m = int.tryParse(parts[1]) ?? 0;
                final y = int.tryParse(parts[0]) ?? 0;
                texto =
                    'Manutenção programada para ${d.toString().padLeft(2, '0')}/${m.toString().padLeft(2, '0')}/$y às $timeStr.${msg.isNotEmpty ? '\n$msg' : ''}';
              }
            }
            final promoButtonLabel = promoLabel.isNotEmpty
                ? promoLabel
                : 'Abrir site — promoção / pagamento';
            return FutureBuilder<String?>(
              key: ValueKey<String>(fp),
              future: SharedPreferences.getInstance().then(
                (p) => p.getString(kMaintenanceDismissedFingerprintPrefsKey),
              ),
              builder: (context, prefSnap) {
                if (prefSnap.data == fp) return const SizedBox.shrink();
                Future<void> dismissMaintBanner() async {
                  final p = await SharedPreferences.getInstance();
                  await p.setString(
                      kMaintenanceDismissedFingerprintPrefsKey, fp);
                  maintenanceDismissSync.value++;
                  if (mounted) setState(() {});
                }

                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: AppColors.logoGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.deepBlueDark.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.workspace_premium_rounded,
                          color: AppColors.amber, size: 30),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxHeight: math.min(
                                        260,
                                        MediaQuery.sizeOf(context).height *
                                            0.34,
                                      ),
                                    ),
                                    child: Scrollbar(
                                      thumbVisibility: texto.length > 200,
                                      child: SingleChildScrollView(
                                        child: Text(
                                          texto,
                                          style: const TextStyle(
                                            fontSize: 14.5,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w700,
                                            height: 1.38,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                TextButton(
                                  onPressed: dismissMaintBanner,
                                  style: TextButton.styleFrom(
                                    foregroundColor: Colors.white,
                                    padding:
                                        const EdgeInsets.only(left: 4, top: 0),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('OK',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w900)),
                                ),
                              ],
                            ),
                            if (appUpdateLinks.hasAnyButton) ...[
                              const SizedBox(height: 12),
                              MaintenanceAppUpdateButtonsOnDarkBanner(
                                links: appUpdateLinks,
                              ),
                            ] else if (showPromoButton) ...[
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  if (showPromoButtonAndroid)
                                    FilledButton.icon(
                                      onPressed: () async {
                                        try {
                                          await openPromoMaintenanceLink(
                                              effectivePromoUrlAndroid);
                                        } catch (_) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Não foi possível abrir o link do Android.'),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      icon: const Icon(Icons.android_rounded,
                                          size: 18),
                                      label: Text(showPromoButtonIos
                                          ? 'Android'
                                          : promoButtonLabel),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: AppColors.deepBlueDark,
                                      ),
                                    ),
                                  if (showPromoButtonIos)
                                    FilledButton.icon(
                                      onPressed: () async {
                                        try {
                                          await openPromoMaintenanceLink(
                                              effectivePromoUrlIos);
                                        } catch (_) {
                                          if (context.mounted) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                    'Não foi possível abrir o link do iPhone.'),
                                              ),
                                            );
                                          }
                                        }
                                      },
                                      icon: const Icon(Icons.apple_rounded,
                                          size: 18),
                                      label: Text(showPromoButtonAndroid
                                          ? 'iPhone'
                                          : promoButtonLabel),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: Colors.white,
                                        foregroundColor: AppColors.deepBlueDark,
                                      ),
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: dismissMaintBanner,
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('OK'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildPeriodSelector() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 400;
        final now = DateTime.now();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              isNarrow
                  ? _dashChipRowScrollOrWrap(
                      maxWidth: constraints.maxWidth,
                      wideThreshold: 10000,
                      spacing: 8,
                      runSpacing: 8,
                      chips: _periods
                          .map((p) => ChoiceChip(
                                label: Text(
                                  p,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: _selectedPeriod == p
                                        ? Colors.white
                                        : const Color(0xFF1A237E),
                                  ),
                                ),
                                selected: _selectedPeriod == p,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedPeriod = p;
                                    if (p == 'Por período' &&
                                        _customRangeStart == null) {
                                      _customRangeStart =
                                          DateTime(now.year, now.month, 1);
                                      _customRangeEnd = now;
                                    }
                                  });
                                },
                                selectedColor: const Color(0xFF2962FF),
                                labelStyle: TextStyle(
                                    color: _selectedPeriod == p
                                        ? Colors.white
                                        : const Color(0xFF1A237E),
                                    fontWeight: FontWeight.w700),
                                backgroundColor: Colors.transparent,
                                side: BorderSide.none,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                              ))
                          .toList(),
                    )
                  : Wrap(
                      spacing: 6,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: _periods
                          .map((p) => ChoiceChip(
                                label: Text(
                                  p,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _selectedPeriod == p
                                        ? Colors.white
                                        : const Color(0xFF1A237E),
                                  ),
                                ),
                                selected: _selectedPeriod == p,
                                onSelected: (_) {
                                  setState(() {
                                    _selectedPeriod = p;
                                    if (p == 'Por período' &&
                                        _customRangeStart == null) {
                                      _customRangeStart =
                                          DateTime(now.year, now.month, 1);
                                      _customRangeEnd = now;
                                    }
                                  });
                                },
                                selectedColor: const Color(0xFF2962FF),
                                labelStyle: TextStyle(
                                    color: _selectedPeriod == p
                                        ? Colors.white
                                        : const Color(0xFF1A237E),
                                    fontWeight: FontWeight.w700),
                                backgroundColor: Colors.transparent,
                                side: BorderSide.none,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ))
                          .toList(),
                    ),
              if (_selectedPeriod == 'Por período') ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _customRangeStart ??
                                DateTime(now.year, now.month, 1),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null && mounted)
                            setState(() => _customRangeStart = picked);
                        },
                        icon:
                            const Icon(Icons.calendar_today_rounded, size: 18),
                        label: Text(
                          'Início: ${DateFormat('dd/MM/yyyy', 'pt_BR').format(_customRangeStart ?? DateTime(now.year, now.month, 1))}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _customRangeEnd ?? now,
                            firstDate: _customRangeStart ?? DateTime(2000),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null && mounted)
                            setState(() => _customRangeEnd = picked);
                        },
                        icon: const Icon(Icons.event_rounded, size: 18),
                        label: Text(
                          'Fim: ${DateFormat('dd/MM/yyyy', 'pt_BR').format(_customRangeEnd ?? now)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  /// Data+hora efetiva do lembrete (date + time HH:mm). Null se sem date.
  static DateTime? _reminderDateTime(Map<String, dynamic> d) {
    final date = (d['date'] as Timestamp?)?.toDate();
    if (date == null) return null;
    final timeStr = (d['time'] ?? '').toString().trim();
    if (timeStr.isEmpty) return DateTime(date.year, date.month, date.day);
    final parts = timeStr.split(':');
    if (parts.length < 2) return DateTime(date.year, date.month, date.day);
    final h = int.tryParse(parts[0]) ?? 0;
    final m = int.tryParse(parts[1]) ?? 0;
    return DateTime(date.year, date.month, date.day, h, m);
  }

  /// Sheet «em aberto»: lista premium; ao tocar só Compromissos ou só Audiências no painel, [filter] restringe.
  Future<void> _showCompromissosAudienciasAbertoSheet(BuildContext context,
      {AgendaAbertoFilter filter = AgendaAbertoFilter.todos}) async {
    await showAgendaEmAbertoSheet(
      context,
      userFsId: _userFsId,
      profile: widget.profile,
      filter: filter,
      hidePeriodFilter: true,
      initialPeriod: _agendaCardPeriod,
      initialCustomStart: _agendaCardCustomStart,
      initialCustomEnd: _agendaCardCustomEnd,
      onVerTudoNaAgenda: widget.onNavigateTo != null
          ? () => widget.onNavigateTo!(7)
          : null,
      buildTile: (ctx, doc, isAudiencia) => AgendaOpenItemCard(
        doc: doc,
        isAudiencia: isAudiencia,
        profile: widget.profile,
        onEdit: () =>
            _showEditReminderFromDashboard(context, doc, isAudiencia),
        onDelete: () async {
          await deleteAgendaReminder(
            context: ctx,
            userDocId: _userFsId,
            reminderDocId: doc.id,
            isAudiencia: isAudiencia,
          );
        },
      ),
    );
  }

  /// Abre edição de compromisso ou audiência a partir do painel da página inicial.
  Future<void> _showEditReminderFromDashboard(BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> doc, bool isAudiencia) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (isAudiencia) {
      await _showEditAudienciaSheet(context, doc);
    } else {
      await _showEditCompromissoSheet(context, doc);
    }
  }

  Future<void> _showEditAudienciaSheet(BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final result = await Navigator.of(context).push<AudienciaFormResult?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AudienciaFormPage(
          profile: widget.profile,
          hasActiveLicense: widget.profile.hasActiveLicense,
          existingDoc: doc,
        ),
      ),
    );
    if (result == null || !context.mounted) return;

    try {
      final msg = await AudienciaReminderService.update(
        userDocId: _userFsId,
        doc: doc,
        result: result,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Erro ao atualizar: ${e.toString().split('\n').first}'),
        ));
      }
    }
  }

  /// Edição completa (mesma tela da Agenda): cor, fim, lembretes, som, etc.
  Future<void> _showEditCompromissoSheet(BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final result = await Navigator.of(context).push<CompromissoFormResult?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => CompromissoFormPage(
          profile: widget.profile,
          hasActiveLicense: widget.profile.hasActiveLicense,
          existingDoc: doc,
        ),
      ),
    );
    if (result == null || !context.mounted) return;

    try {
      final msg = await AgendaReminderEditService.persistCompromissoEdit(
        doc: doc,
        result: result,
        userDocId: _userFsId,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text('Erro ao atualizar: ${e.toString().split('\n').first}'),
        ));
      }
    }
  }

  /// Resumo de Audiências e Compromissos em aberto (audiência/compromisso: 24h no painel após o horário; baixa automática depois).
  Widget _buildAgendaResumo(DateTime rangeStart, DateTime rangeEnd) {
    final now = DateTime.now();
    final queryStart = rangeStart.subtract(const Duration(days: 3));
    final queryEnd = rangeEnd.add(const Duration(days: 1));

    final remindersRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_userFsId)
        .collection('reminders');
    final boundedQuery = remindersRef
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(queryStart))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(queryEnd))
        .limit(500);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: () async* {
        try {
          final cached = await boundedQuery.get(
            const GetOptions(source: Source.cache),
          );
          yield cached;
        } catch (_) {}
        yield* boundedQuery.snapshots();
      }(),
      builder: (context, snap) {
        if (snap.hasError) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 500;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _agendaResumoCardSkeleton(isNarrow),
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Não foi possível carregar o resumo da agenda.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textMuted,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        }
        if (!snap.hasData) {
          return LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 500;
              return _agendaResumoCardSkeleton(isNarrow);
            },
          );
        }
        _scheduleAgendaAutoCloseFromSnapshot(snap.data!, remindersRef);

        int compromissos = 0;
        int audiencias = 0;
        final docs = snap.data!.docs;
        for (final doc in docs) {
          final d = doc.data();
          if (!YearlyCommitmentRepeatService.shouldShowInAgendaList(
            d,
            docId: doc.id,
          )) {
            continue;
          }
          if (!agendaReminderBelongsInAgendaModule(d)) continue;
          final date = (d['date'] as Timestamp?)?.toDate();
          if (date == null) continue;
          if (agendaShouldAutoCloseNow(d, now)) {
            continue;
          }
          if (!agendaStillCountedAsOpenOnPanel(d, now)) continue;
          if (!agendaReminderDayInRange(d, rangeStart, rangeEnd)) continue;
          final type = (d['type'] ?? 'compromisso').toString();
          if (type == 'audiencia')
            audiencias++;
          else
            compromissos++;
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 500;
            return Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.12),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.deepBlueDark.withValues(alpha: 0.08),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    height: 4,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: AppColors.logoGradient,
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  colors: AppColors.logoGradient,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.deepBlueDark
                                        .withValues(alpha: 0.2),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.event_note_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Audiências e Compromissos em aberto',
                                    style: TextStyle(
                                      fontSize: isNarrow ? 14 : 15,
                                      fontWeight: FontWeight.w900,
                                      color: AppColors.deepBlueDark,
                                      letterSpacing: -0.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Período do resumo em aberto',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        AgendaPeriodFilterBar(
                          dense: true,
                          layout: AgendaPeriodFilterBarLayout.segmented,
                          style: AgendaPeriodFilterBarStyle.standard,
                          initialPeriod: _agendaCardPeriod,
                          initialCustomStart: _agendaCardCustomStart,
                          initialCustomEnd: _agendaCardCustomEnd,
                          onChanged: (v) {
                            setState(() {
                              _agendaCardPeriod = v.period;
                              if (v.period == AgendaPeriodKeys.porPeriodo) {
                                _agendaCardCustomStart = v.rangeStart;
                                _agendaCardCustomEnd = v.rangeEnd;
                              }
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () =>
                                _showCompromissosAudienciasAbertoSheet(
                              context,
                              filter:
                                  AgendaAbertoFilter.apenasAudiencias,
                            ),
                            child: AgendaResumoCountCard(
                              icon: Icons.gavel_rounded,
                              label: 'Audiências',
                              count: audiencias,
                              palette: AgendaResumoCountPalette.audiencia(),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () =>
                                _showCompromissosAudienciasAbertoSheet(
                              context,
                              filter:
                                  AgendaAbertoFilter.apenasCompromissos,
                            ),
                            child: AgendaResumoCountCard(
                              icon: Icons.person_outline_rounded,
                              label: 'Compromissos',
                              count: compromissos,
                              palette: AgendaResumoCountPalette.compromisso(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _showCompromissosAudienciasAbertoSheet(
                            context,
                            filter: AgendaAbertoFilter.todos,
                          ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.touch_app_rounded,
                                size: 14,
                                color: AppColors.primary),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Toque em cada cartão para ver só audiências ou só compromissos (link da sala e anexo). Toque aqui para ver ambos.',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Esqueleto do card de agenda enquanto os dados ainda não carregaram (evita mostrar 0 incorreto).
  Widget _agendaResumoCardSkeleton(bool isNarrow) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        children: [
          Container(
            height: 4,
            color: AppColors.primary.withValues(alpha: 0.2),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  width: isNarrow ? 160 : 220,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFBBD4FF),
                              Color(0xFFD6E6FF),
                              Color(0xFFF0F6FF),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Color(0xFF5B7FD6),
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Container(
                        height: 72,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFF7FE8D8),
                              Color(0xFFB8F5EC),
                              Color(0xFFE8FCF8),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Color(0xFF14B8A6),
                            width: 1.5,
                          ),
                        ),
                      ),
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

  Widget _buildSectionTitle(String title) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          width: 4,
          height: 22,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1A237E),
              letterSpacing: -0.25,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  /// Retorna o label do período com ano (ex.: "Fev/2026", "2026", "22/02/2026").
  String _periodLabel(DateTime rangeStart, DateTime rangeEnd, String period) {
    switch (period) {
      case 'Diário':
        return DateFormat('dd/MM/yyyy').format(rangeStart);
      case 'Semanal':
        return '${DateFormat('dd/MM').format(rangeStart)} - ${DateFormat('dd/MM/yyyy').format(rangeEnd)}';
      case 'Mensal':
        return DateFormat('MMM/yyyy', 'pt_BR').format(rangeStart);
      case 'Mês anterior':
        return DateFormat('MMM/yyyy', 'pt_BR').format(rangeStart);
      case 'Anual':
        return '${rangeStart.year}';
      case 'Por período':
        return '${DateFormat('dd/MM/yyyy').format(rangeStart)} - ${DateFormat('dd/MM/yyyy').format(rangeEnd)}';
      default:
        return DateFormat('MMM/yyyy', 'pt_BR').format(rangeStart);
    }
  }

  /// Erro no stream `transactions` (rede/sessão): não mostrar R\$ 0 como se não houvesse dados.
  Widget _dashboardFinanceFirestoreErrorBanner(VoidCallback onRetry) {
    return Material(
      color: Colors.orange.shade50,
      borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.cloud_off_rounded,
                    color: Colors.orange.shade900, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Não foi possível sincronizar os movimentos. Os seus dados não foram apagados — verifique a rede ou saia e entre de novo.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade900,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 20),
              label: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }

  /// Banner quando há lançamentos pendentes com vencimento hoje. Alerta manual: "Hoje vence: ... Confirme o pagamento."
  Widget _buildVenceHojeBanner() {
    final today =
        DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    final todayEnd = DateTime(DateTime.now().year, DateTime.now().month,
        DateTime.now().day, 23, 59, 59);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(_userFsId)
          .collection('transactions')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(todayEnd))
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) return const SizedBox.shrink();
        final docs = snap.data?.docs ?? [];
        final pendentesHoje = <Map<String, dynamic>>[];
        for (final doc in docs) {
          final d = doc.data();
          if ((d['status'] ?? 'paid').toString() != 'paid') {
            final m = Map<String, dynamic>.from(d);
            m['id'] = doc.id;
            pendentesHoje.add(m);
          }
        }
        if (pendentesHoje.isEmpty) return const SizedBox.shrink();
        final first = pendentesHoje.first;
        final desc = (first['description'] ?? first['category'] ?? 'Lançamento')
            .toString();
        final amount = (first['amount'] ?? 0).toDouble();
        final isIncome = (first['type'] ?? 'expense').toString() == 'income';
        final label = isIncome ? 'Receita' : 'Despesa';
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.logoOrange.withOpacity(0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.logoOrange.withOpacity(0.4)),
          ),
          child: Row(
            children: [
              Icon(Icons.today_rounded, color: AppColors.logoOrange, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Hoje vence: ${desc.isEmpty ? label : desc}',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                          color: Colors.grey.shade800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${SensitiveBalancePreferences.formatBrl(amount.abs(), hidden: _hideSensitiveBalances)} · Clique em Confirmar pagamento no Financeiro ou no painel acima.',
                      style:
                          TextStyle(fontSize: 11, color: Colors.grey.shade700),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (widget.onNavigateTo != null)
                TextButton(
                  onPressed: () => widget.onNavigateTo!(1),
                  child: const Text('Ir ao Financeiro'),
                ),
            ],
          ),
        );
      },
    );
  }

  void _ensureDashboardOpeningBalance(DateTime limiteAnterior) {
    final key = '${limiteAnterior.year}-${limiteAnterior.month}-${limiteAnterior.day}';
    if (_dashboardOpeningBalancePeriodKey == key &&
        _dashboardOpeningBalanceCached != null) {
      return;
    }
    _dashboardOpeningBalancePeriodKey = key;
    final peek = FinanceOpeningBalanceService.peekCached(
      uid: widget.uid,
      periodStart: limiteAnterior,
      loadAccounts: false,
    );
    if (peek != null) {
      _dashboardOpeningBalanceCached = peek.total;
    }
    unawaited(_loadDashboardOpeningBalance(limiteAnterior));
  }

  Future<void> _loadDashboardOpeningBalance(DateTime limiteAnterior) async {
    final key =
        '${limiteAnterior.year}-${limiteAnterior.month}-${limiteAnterior.day}';
    try {
      final open = await FinanceOpeningBalanceService.load(
        uid: widget.uid,
        periodStart: limiteAnterior,
        loadAccounts: false,
      );
      if (!mounted || _dashboardOpeningBalancePeriodKey != key) return;
      setState(() => _dashboardOpeningBalanceCached = open.total);
    } catch (_) {}
  }

  String _dashboardFinanceKpiCacheKey(DateTime rangeStart, DateTime rangeEnd) {
    return '${rangeStart.millisecondsSinceEpoch}|${rangeEnd.millisecondsSinceEpoch}|$_userFsId';
  }

  void _ensureDashboardFinanceKpis(DateTime rangeStart, DateTime rangeEnd) {
    if (_userFsId.isEmpty) return;
    final key = _dashboardFinanceKpiCacheKey(rangeStart, rangeEnd);
    if (_dashboardFinanceKpiKey == key &&
        _dashboardFinanceIncomeCached != null &&
        _dashboardFinanceExpenseCached != null) {
      return;
    }
    _dashboardFinanceKpiKey = key;
    final peek = FinanceServerTotals.peekCached(
      uid: _userFsId,
      from: rangeStart,
      to: rangeEnd,
      statusFilter: 'paid',
    );
    if (peek != null) {
      _dashboardFinanceIncomeCached = peek.income;
      _dashboardFinanceExpenseCached = peek.expense;
      _dashboardFinancePendingCountCached = peek.pendingExpenseCount;
    }
    unawaited(_loadDashboardFinanceKpis(rangeStart, rangeEnd, key));
  }

  Future<void> _loadDashboardFinanceKpis(
    DateTime rangeStart,
    DateTime rangeEnd,
    String key,
  ) async {
    if (!mounted || _dashboardFinanceKpiKey != key) return;
    setState(() => _dashboardFinanceKpiLoading = true);
    try {
      final totals = await FinanceServerTotals.load(
        uid: _userFsId,
        from: rangeStart,
        to: rangeEnd,
        statusFilter: 'paid',
      );
      if (!mounted || _dashboardFinanceKpiKey != key) return;
      setState(() {
        _dashboardFinanceIncomeCached = totals.income;
        _dashboardFinanceExpenseCached = totals.expense;
        _dashboardFinancePendingCountCached = totals.pendingExpenseCount;
        _dashboardFinanceKpiLoading = false;
      });
    } catch (_) {
      if (mounted && _dashboardFinanceKpiKey == key) {
        setState(() => _dashboardFinanceKpiLoading = false);
      }
    }
  }

  /// Faixa verde no topo com Receitas / Despesas / Saldo do período (campos em retângulos brancos).
  /// Inclui Saldo de abertura (saldo anterior ao início do período) quando aplicável.
  Widget _buildBlueSummaryBand(
      DateTime rangeStart, DateTime rangeEnd, String period) {
    final periodLabel = _periodLabel(rangeStart, rangeEnd, period);
    final limiteAnterior =
        DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    _ensureDashboardOpeningBalance(limiteAnterior);
    _ensureDashboardFinanceKpis(rangeStart, rangeEnd);

    if (_userFsId.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    final receitas = _dashboardFinanceIncomeCached;
    final despesasPagas = _dashboardFinanceExpenseCached;
    final despesasPendentesCount = _dashboardFinancePendingCountCached;
    final kpiLoading = _dashboardFinanceKpiLoading &&
        receitas == null &&
        despesasPagas == null;

    if (kpiLoading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
          child: SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        ),
      );
    }

    final receitasVal = receitas ?? 0.0;
    final despesasVal = despesasPagas ?? 0.0;
    final saldoPeriodo = receitasVal - despesasVal;
    final saldoAnterior = _dashboardOpeningBalanceCached ?? 0.0;
    final saldoAcumulado = saldoAnterior + saldoPeriodo;
    return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF14532D), Color(0xFF166534), Color(0xFF15803D)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
            boxShadow: [
              BoxShadow(
                color: AppColors.saldoPositive.withValues(alpha: 0.32),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      periodLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.95),
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  IconButton(
                    tooltip: _hideSensitiveBalances
                        ? 'Mostrar valores'
                        : 'Ocultar valores',
                    onPressed: () async {
                      final v = !_hideSensitiveBalances;
                      await SensitiveBalancePreferences.set(v);
                      if (mounted) setState(() => _hideSensitiveBalances = v);
                    },
                    icon: Icon(
                      _hideSensitiveBalances
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.white.withValues(alpha: 0.95),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _summaryCard(
                label: 'Saldo de abertura',
                value: saldoAnterior,
                labelAndValueColor: saldoAnterior >= 0
                    ? AppColors.saldoPositive
                    : AppColors.saldoNegative,
                hint: 'Toque para gráficos',
                hideAmount: _hideSensitiveBalances,
                onTap: () => _openDashboardFinanceInsight(
                  context,
                  scope: FinanceInsightScope.balance,
                  rangeStart: rangeStart,
                  rangeEnd: rangeEnd,
                  openingBalanceHint: saldoAnterior,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _summaryCard(
                      label: 'Receitas',
                      value: receitasVal,
                      labelAndValueColor: AppColors.saldoPositive,
                      hint: 'Toque para gráficos',
                      hideAmount: _hideSensitiveBalances,
                      onTap: () => _openDashboardFinanceInsight(
                        context,
                        scope: FinanceInsightScope.balance,
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd,
                        openingBalanceHint: saldoAnterior,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _summaryCard(
                      label: 'Despesas pagas',
                      value: despesasVal,
                      labelAndValueColor: AppColors.saldoNegative,
                      hint: despesasPendentesCount > 0
                          ? '$despesasPendentesCount pendente(s) · Toque para lançamentos'
                          : 'Toque para lançamentos',
                      hideAmount: _hideSensitiveBalances,
                      onTap: () => _openDashboardFinanceInsight(
                        context,
                        scope: FinanceInsightScope.balance,
                        rangeStart: rangeStart,
                        rangeEnd: rangeEnd,
                        openingBalanceHint: saldoAnterior,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: saldoAcumulado < 0
                        ? _summaryCardSaldoNegativo(
                            saldoAcumulado,
                            hideAmount: _hideSensitiveBalances,
                            onTap: () => _openDashboardFinanceInsight(
                              context,
                              scope: FinanceInsightScope.balance,
                              rangeStart: rangeStart,
                              rangeEnd: rangeEnd,
                              openingBalanceHint: saldoAnterior,
                            ),
                          )
                        : _summaryCard(
                            label: 'Saldo (acum.)',
                            value: saldoAcumulado,
                            labelAndValueColor: AppColors.saldoPositive,
                            hint: 'Toque para gráficos',
                            hideAmount: _hideSensitiveBalances,
                            onTap: () => _openDashboardFinanceInsight(
                              context,
                              scope: FinanceInsightScope.balance,
                              rangeStart: rangeStart,
                              rangeEnd: rangeEnd,
                              openingBalanceHint: saldoAnterior,
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _openDashboardAccountsSaldoSheet(
                      context, rangeStart, rangeEnd),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.9), width: 1),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 8,
                            offset: const Offset(0, 2))
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                AppColors.primary.withValues(alpha: 0.85),
                                AppColors.accent.withValues(alpha: 0.75)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.pie_chart_outline_rounded,
                              color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Saldo por contas',
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Color(0xFF14532D)),
                              ),
                              Text(
                                'Corrente, poupança e cartões — toque para ver',
                                style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            color: Colors.grey.shade600),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: widget.profile.hasActiveLicense
                      ? () => _openDashboardPdfStyleSheet(
                            context,
                            rangeStart,
                            rangeEnd,
                            cachedDocs: const <QueryDocumentSnapshot<Map<String, dynamic>>>[],
                            openingBalanceHint: saldoAnterior,
                          )
                      : () =>
                          mostrarAvisoSeLicencaInativa(context, widget.profile),
                  icon: const Icon(Icons.picture_as_pdf_rounded, size: 20),
                  label: const Text('Exportar PDF'),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE65100),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                  ),
                ),
              ),
            ],
          ),
        );
  }

  /// Quadro azul claro: receitas pendentes. Respeita preferências de receitas fixas (igual Financeiro).
  Widget _buildReceitasPendentesBand(BuildContext context) {
    return StreamBuilder<List<FinanceAccount>>(
      stream: FinanceAccountsService().streamAccounts(_userFsId),
      builder: (context, accSnap) {
        final ccIds = FinanceAccountBalanceUtils.creditCardAccountIds(accSnap.data ?? const []);
        return StreamBuilder<Map<String, dynamic>>(
      stream: FixedIncomePreferencesService().watch(_userFsId),
      builder: (context, prefsSnap) {
        final showInPending = prefsSnap.data?['showInPending'] as bool? ?? true;
        final monthsAhead =
            (prefsSnap.data?['pendingMonthsAhead'] as int?)?.clamp(1, 12) ??
                AppBusinessRules.pendingMonthsAheadDefault;
        final limitDate = DateTime(
            DateTime.now().year, DateTime.now().month + monthsAhead, 1);
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: financeTransactionsPendingSnapshots(uid: _userFsId, type: 'income'),
          builder: (context, snap) {
            if (snap.hasError) {
              return _dashboardFinanceFirestoreErrorBanner(() {
                if (mounted) setState(() {});
              });
            }
            double totalPendentes = 0;
            final listPendentes = <Map<String, dynamic>>[];
            for (final doc in snap.data?.docs ?? []) {
              final d = Map<String, dynamic>.from(doc.data());
              d['id'] = doc.id;
              final type = (d['type'] ?? 'expense').toString();
              final status = (d['status'] ?? 'paid').toString();
              if (type != 'income' || status == 'paid') continue;
              if (FinanceAccountBalanceUtils.isOnCreditCardAccount(d, ccIds)) continue;
              if (!showInPending &&
                  (d['fixedIncomeId'] ?? '').toString().isNotEmpty) continue;
              final dateTs = d['date'];
              if (dateTs is Timestamp) {
                final dt = dateTs.toDate();
                if (dt.isAfter(limitDate)) continue;
              }
              final amount = (d['amount'] ?? 0).toDouble().abs();
              totalPendentes += amount;
              listPendentes.add(d);
            }
            listPendentes.sort((a, b) {
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
                onTap: () =>
                    _abrirListaReceitasPendentes(context, listPendentes),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        blueLight,
                        blueLight.withOpacity(0.9),
                        blueLightDark
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: blueLight.withOpacity(0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
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
                        child: const Icon(Icons.schedule_rounded,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Receitas pendentes',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color:
                                        Colors.white.withValues(alpha: 0.98))),
                            const SizedBox(height: 4),
                            Text(
                              '${listPendentes.length} lançamento(s) em aberto · Toque para ver',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.85)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          SensitiveBalancePreferences.formatBrl(totalPendentes,
                              hidden: _hideSensitiveBalances),
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white),
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
      },
    );
  }

  /// Quadro laranja: despesas pendentes. Respeita preferências (mostrar fixas, próximos X meses) — igual módulo Financeiro.
  Widget _buildDespesasPendentesBand(BuildContext context) {
    return StreamBuilder<List<FinanceAccount>>(
      stream: FinanceAccountsService().streamAccounts(_userFsId),
      builder: (context, accSnap) {
        final ccIds = FinanceAccountBalanceUtils.creditCardAccountIds(accSnap.data ?? const []);
        return StreamBuilder<Map<String, dynamic>>(
      stream: FixedExpensePreferencesService().watch(_userFsId),
      builder: (context, prefsSnap) {
        final showInPending = prefsSnap.data?['showInPending'] as bool? ?? true;
        final monthsAhead =
            (prefsSnap.data?['pendingMonthsAhead'] as int?)?.clamp(1, 12) ??
                AppBusinessRules.pendingMonthsAheadDefault;
        final limitDate = DateTime(
            DateTime.now().year, DateTime.now().month + monthsAhead, 1);
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: financeTransactionsPendingSnapshots(uid: _userFsId, type: 'expense'),
          builder: (context, snap) {
            if (snap.hasError) {
              return _dashboardFinanceFirestoreErrorBanner(() {
                if (mounted) setState(() {});
              });
            }
            double totalPendentes = 0;
            final listPendentes = <Map<String, dynamic>>[];
            for (final doc in snap.data?.docs ?? []) {
              final d = Map<String, dynamic>.from(doc.data());
              d['id'] = doc.id;
              final type = (d['type'] ?? 'expense').toString();
              final status = (d['status'] ?? 'paid').toString();
              if (type == 'income' || status == 'paid') continue;
              if (FinanceAccountBalanceUtils.isOnCreditCardAccount(d, ccIds)) continue;
              if (!showInPending &&
                  (d['fixedExpenseId'] ?? '').toString().isNotEmpty) continue;
              final dateTs = d['date'];
              if (dateTs is Timestamp) {
                final dt = dateTs.toDate();
                if (dt.isAfter(limitDate)) continue;
              }
              final amount = (d['amount'] ?? 0).toDouble().abs();
              totalPendentes += amount;
              listPendentes.add(d);
            }
            listPendentes.sort((a, b) {
              final ta = (a['date'] as Timestamp?)?.toDate();
              final tb = (b['date'] as Timestamp?)?.toDate();
              if (ta == null || tb == null) return 0;
              return ta.compareTo(tb);
            });
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () =>
                    _abrirListaDespesasPendentes(context, listPendentes),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        AppColors.logoOrange,
                        AppColors.logoOrange.withOpacity(0.85),
                        const Color(0xFFEA580C),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.logoOrange.withOpacity(0.35),
                          blurRadius: 12,
                          offset: const Offset(0, 4))
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
                        child: const Icon(Icons.schedule_rounded,
                            color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Despesas pendentes',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color:
                                        Colors.white.withValues(alpha: 0.98))),
                            const SizedBox(height: 4),
                            Text(
                              '${listPendentes.length} lançamento(s) em aberto · Toque para ver',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.85)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          SensitiveBalancePreferences.formatBrl(totalPendentes,
                              hidden: _hideSensitiveBalances),
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: Colors.white),
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
      },
    );
  }

  /// Card roxo: fatura de cartão em aberto (separado de despesas pendentes normais).
  Widget _buildFaturaEmAbertoBand(BuildContext context) {
    return StreamBuilder<List<FinanceAccount>>(
      stream: FinanceAccountsService().streamAccounts(_userFsId),
      builder: (context, accSnap) {
        final accounts = accSnap.data ?? const <FinanceAccount>[];
        final ccIds = FinanceAccountBalanceUtils.creditCardAccountIds(accounts);
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: financeTransactionsPendingSnapshots(uid: _userFsId, type: 'expense'),
          builder: (context, snap) {
            final docs = snap.data?.docs ?? const [];
            final faturaByCard = FinanceAccountBalanceUtils.faturaAbertaByCardId(
              docs,
              creditCardIds: ccIds,
            );
            final total = FinanceAccountBalanceUtils.totalFaturaEmAberto(faturaByCard);
            final count = FinanceAccountBalanceUtils.countPendingExpensesOnCreditCards(docs, ccIds);
            final cards = FinanceAccountBalanceUtils.creditCardProducts(accounts);
            if (cards.isEmpty) return const SizedBox.shrink();
            return FinanceFaturaEmAbertoBand(
              totalFatura: total,
              lancamentoCount: count,
              cartaoCount: cards.length,
              hideAmount: _hideSensitiveBalances,
              amountFormatter: (v, {required hidden}) =>
                  SensitiveBalancePreferences.formatBrl(v, hidden: hidden),
              onTap: snap.hasError
                  ? () {}
                  : () => _openFaturaEmAbertoFromDashboard(context, faturaByCard, accounts),
            );
          },
        );
      },
    );
  }

  FinanceFaturaSheetHandlers _dashboardFaturaHandlers() => FinanceFaturaSheetHandlers(
        onConfirmFaturaPayment: _confirmarPagamentoFaturaCartaoDashboard,
        onEditTransaction: (c, docId, current, type) async {
          final e = Map<String, dynamic>.from(current);
          e['id'] = docId;
          if (type == 'income') {
            await _editarReceitaDashboard(c, e);
          } else {
            await _editarLancamentoDashboard(c, e);
          }
        },
        onDeleteTransaction: _excluirLancamentoDashboard,
        onDeleteBatch: _excluirLancamentoBatchDashboard,
        onAttachReceipt: _attachReceiptDashboard,
      );

  void _openFaturaEmAbertoFromDashboard(
    BuildContext context,
    Map<String, double> faturaByCard,
    List<FinanceAccount> accounts,
  ) {
    unawaited(
      FinanceFaturaEmAbertoHub.open(
        context,
        uid: widget.uid,
        profile: widget.profile,
        allAccounts: accounts,
        faturaByCardId: faturaByCard,
        handlers: _dashboardFaturaHandlers(),
      ),
    );
  }

  void _openDashboardCreditCardFaturaSheet(
    BuildContext context,
    FinanceAccount card,
    List<FinanceAccount> accounts,
  ) {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final h = _dashboardFaturaHandlers();
    unawaited(
      FinanceCreditCardFaturaSheet.show(
        context,
        uid: widget.uid,
        profile: widget.profile,
        cardAccount: card,
        allAccounts: accounts,
        optimisticPaidIds: const {},
        onConfirmFaturaPayment: h.onConfirmFaturaPayment,
        onEditTransaction: h.onEditTransaction,
        onDeleteTransaction: h.onDeleteTransaction,
        onDeleteBatch: h.onDeleteBatch,
        onAttachReceipt: h.onAttachReceipt,
      ),
    );
  }

  Future<void> _confirmarPagamentoFaturaCartaoDashboard(
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
    final txCol = FirebaseFirestore.instance
        .collection('users')
        .doc(_userFsId)
        .collection('transactions');
    try {
      await commitFinanceConfirmPaymentBatch(
        txCol: txCol,
        docIds: unique,
        uid: widget.uid,
        result: result,
        creditCardFaturaPayment: true,
      );
      if (!context.mounted) return;
      FinanceTransactionsHub.notifyMutated(uid: widget.uid);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            unique.length > 1
                ? 'Fatura: ${unique.length} lançamentos pagos.'
                : 'Pagamento da fatura confirmado.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao pagar fatura: ${e.toString().split('\n').first}'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  /// Card retangular branco para cada valor (Receitas verde, Despesas vermelho, Saldo verde/vermelho).
  Widget _summaryCard({
    required String label,
    required double value,
    required Color labelAndValueColor,
    String? hint,
    bool hideAmount = false,
    VoidCallback? onTap,
  }) {
    final inner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.deepBlue.withValues(alpha: 0.08), width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: labelAndValueColor),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              SensitiveBalancePreferences.formatBrl(value, hidden: hideAmount),
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: labelAndValueColor),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          if (hint != null) ...[
            const SizedBox(height: 4),
            Text(hint,
                style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                textAlign: TextAlign.center),
          ],
        ],
      ),
    );
    if (onTap == null) return inner;
    return Material(
      color: Colors.transparent,
      child: InkWell(
          onTap: onTap, borderRadius: BorderRadius.circular(12), child: inner),
    );
  }

  /// Saldo negativo: vermelho dentro de card retangular branco.
  Widget _summaryCardSaldoNegativo(double value,
      {bool hideAmount = false, VoidCallback? onTap}) {
    final inner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppColors.saldoNegative.withValues(alpha: 0.16), width: 1),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 12,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Saldo (acum.)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.saldoNegative),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center),
          const SizedBox(height: 7),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              SensitiveBalancePreferences.formatBrl(value, hidden: hideAmount),
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  color: AppColors.saldoNegative),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(height: 4),
            Text('Toque para gráficos',
                style: TextStyle(fontSize: 9, color: Colors.grey.shade600),
                textAlign: TextAlign.center),
          ],
        ],
      ),
    );
    if (onTap == null) return inner;
    return Material(
      color: Colors.transparent,
      child: InkWell(
          onTap: onTap, borderRadius: BorderRadius.circular(12), child: inner),
    );
  }

  /// Saldo líquido por conta no período (só lançamentos pagos, mesma lógica da faixa verde).
  Map<String, double> _netByFinanceAccountInPeriod(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final m = <String, double>{};
    final rs = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final re =
        DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day, 23, 59, 59);
    for (final doc in docs) {
      final d = doc.data();
      final type = (d['type'] ?? 'expense').toString();
      final isPending = (d['status'] ?? 'paid').toString() != 'paid';
      if (isPending) continue;
      final effectiveDate = FinanceLineOpening.effectiveDateTimeFromMap(d);
      if (effectiveDate == null ||
          effectiveDate.isBefore(rs) ||
          effectiveDate.isAfter(re)) {
        continue;
      }
      final aid = (d['financeAccountId'] ?? '').toString().trim();
      if (aid.isEmpty) continue;
      final amount = (d['amount'] ?? 0).toDouble();
      final delta = type == 'income' ? amount : -amount.abs();
      m[aid] = (m[aid] ?? 0) + delta;
    }
    return m;
  }

  /// Saldo de abertura **por conta** (lançamentos pagos com data efetiva antes do início do período).
  /// Igual [FinanceScreen]._loadSaldoAberturaPorContaFor — necessário para o modal bater com «Saldo (acum.)».
  Map<String, double> _openingNetByFinanceAccountBefore(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime periodStartDay,
  ) {
    final start =
        DateTime(periodStartDay.year, periodStartDay.month, periodStartDay.day);
    final byAcc = <String, double>{};
    for (final doc in docs) {
      final d = doc.data();
      final ts = d['date'];
      final effectiveDate = FinanceLineOpening.effectiveDateTimeFromMap(d) ??
          (ts is Timestamp ? ts.toDate() : null);
      if (effectiveDate == null || !effectiveDate.isBefore(start)) continue;
      final isPaid = (d['status'] ?? 'paid').toString() == 'paid';
      if (!isPaid) continue;
      final aid = (d['financeAccountId'] ?? '').toString().trim();
      if (aid.isEmpty) continue;
      final amount = (d['amount'] ?? 0).toDouble();
      final type = (d['type'] ?? 'expense').toString();
      final delta = type == 'income' ? amount : -amount.abs();
      byAcc[aid] = (byAcc[aid] ?? 0) + delta;
    }
    return byAcc;
  }

  /// Saldo de abertura total (todas as transações antes do período), igual ao cartão «Saldo de abertura» da faixa verde.
  double _openingSaldoTotalBefore(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime periodStartDay,
  ) {
    final start =
        DateTime(periodStartDay.year, periodStartDay.month, periodStartDay.day);
    double saldo = 0;
    for (final doc in docs) {
      final d = doc.data();
      final ts = d['date'];
      if (ts is! Timestamp) continue;
      final date = ts.toDate();
      final effectiveDate = FinanceLineOpening.effectiveDateTimeFromMap(d) ?? date;
      if (!effectiveDate.isBefore(start)) continue;
      final isPaid = (d['status'] ?? 'paid').toString() == 'paid';
      if (!isPaid) continue;
      final amount = (d['amount'] ?? 0).toDouble();
      final type = (d['type'] ?? 'expense').toString();
      if (type == 'income') {
        saldo += amount;
      } else {
        saldo -= amount.abs();
      }
    }
    return saldo;
  }

  Map<String, double> _mergeOpeningAndPeriodByAccount(
    Map<String, double> openingByAccount,
    Map<String, double> periodByAccount,
  ) {
    final out = <String, double>{...openingByAccount};
    periodByAccount.forEach((id, val) {
      out[id] = (out[id] ?? 0) + val;
    });
    return out;
  }

  /// Saldo líquido no período dos lançamentos pagos **sem** conta — entram no «Saldo (acum.)»
  /// mas não aparecem em nenhuma linha de banco até atribuir conta.
  double _periodNetUnassigned(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final rs = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final re =
        DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day, 23, 59, 59);
    var net = 0.0;
    for (final doc in docs) {
      final d = doc.data();
      if ((d['status'] ?? 'paid').toString() != 'paid') continue;
      final aid = (d['financeAccountId'] ?? '').toString().trim();
      if (aid.isNotEmpty) continue;
      final effectiveDate = FinanceLineOpening.effectiveDateTimeFromMap(d);
      if (effectiveDate == null ||
          effectiveDate.isBefore(rs) ||
          effectiveDate.isAfter(re)) {
        continue;
      }
      final amount = (d['amount'] ?? 0).toDouble();
      final type = (d['type'] ?? 'expense').toString();
      net += type == 'income' ? amount : -amount.abs();
    }
    return net;
  }

  Future<void> _openDashboardFinanceInsight(
    BuildContext context, {
    required FinanceInsightScope scope,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    String? financeAccountFilterId,
    String? financeAccountFilterLabel,
    double? openingBalanceHint,
    Map<String, double>? openingByAccountHint,
  }) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final from = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final to =
        DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day, 23, 59, 59);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (ctx) => FinanceInsightSheet(
        uid: _userFsId,
        initialScope: scope,
        initialFrom: from,
        initialTo: to,
        statusFilter: 'paid',
        search: '',
        financeAccountFilterId: financeAccountFilterId,
        financeAccountFilterLabel: financeAccountFilterLabel,
        openingBalanceHint: openingBalanceHint,
        openingByAccountHint: openingByAccountHint,
        onEdit: (docId, current, type) async {
          final e = Map<String, dynamic>.from(current);
          e['id'] = docId;
          if (type == 'income') {
            await _editarReceitaDashboard(context, e);
          } else {
            await _editarLancamentoDashboard(context, e);
          }
        },
        onDelete: (docId) => _excluirLancamentoDashboard(context, docId),
      ),
    );
  }

  Future<void> _openDashboardAccountsSaldoSheet(
    BuildContext context,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.55,
        minChildSize: 0.32,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollController) => Container(
          decoration: financePremiumSheetDecoration(surfaceTint: AppColors.primary),
          child: StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
            stream: financeTransactionsPeriodDocs(
              uid: _userFsId,
              rangeStart: rangeStart,
              rangeEnd: rangeEnd,
            ),
            builder: (context, txSnap) {
              final periodDocs = txSnap.data ??
                  const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
              final periodStart =
                  DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
              final openingPeek = FinanceOpeningBalanceService.peekCached(
                uid: widget.uid,
                periodStart: periodStart,
                loadAccounts: true,
              );
              return FutureBuilder<({double total, Map<String, double> byAccount})>(
                future: FinanceOpeningBalanceService.load(
                  uid: widget.uid,
                  periodStart: periodStart,
                  loadAccounts: true,
                ),
                initialData: openingPeek,
                builder: (context, openSnap) {
                  final openingById = Map<String, double>.from(
                    openSnap.data?.byAccount ?? const <String, double>{},
                  );
                  final openingTotal = openSnap.data?.total ?? 0.0;
                  final netById =
                      _netByFinanceAccountInPeriod(periodDocs, rangeStart, rangeEnd);
                  final mergedById =
                      _mergeOpeningAndPeriodByAccount(openingById, netById);
                  var sumOpeningAssigned = 0.0;
                  for (final v in openingById.values) {
                    sumOpeningAssigned += v;
                  }
                  final orphanOpening = openingTotal - sumOpeningAssigned;
                  final showOrphanOpening = orphanOpening.abs() > 0.005;
                  final periodOrphan =
                      _periodNetUnassigned(periodDocs, rangeStart, rangeEnd);
                  final showPeriodOrphan = periodOrphan.abs() > 0.005;
                  final trailingSaldoTiles =
                      (showOrphanOpening ? 1 : 0) + (showPeriodOrphan ? 1 : 0);
                  final docs = periodDocs;
              return StreamBuilder<List<FinanceAccount>>(
                stream: FinanceAccountsService().streamAccounts(_userFsId),
                builder: (context, accSnap) {
                  final accounts = accSnap.data ?? const <FinanceAccount>[];
                  final ccIds =
                      FinanceAccountBalanceUtils.creditCardAccountIds(accounts);
                  // Diferencia "ainda carregando do servidor" de "realmente
                  // sem contas cadastradas". Sem isso o usuário via "Cadastre
                  // contas em Financeiro" mesmo quando tinha contas — só não
                  // tinham chegado ainda do servidor.
                  final accountsLoading = !accSnap.hasData &&
                      accSnap.connectionState == ConnectionState.waiting;
                  return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: financeTransactionsPendingSnapshots(
                      uid: _userFsId,
                      type: 'expense',
                    ),
                    builder: (context, pendingSnap) {
                      final pendingDocs =
                          pendingSnap.data?.docs ?? const [];
                      final faturaByCard =
                          FinanceAccountBalanceUtils.faturaAbertaByCardId(
                        pendingDocs,
                        creditCardIds: ccIds,
                      );
                      return Column(
                    children: [
                      FinancePremiumSheetHeader(
                        title: 'Saldo por contas',
                        subtitle:
                            'Conta corrente: lançamentos e gráficos · Cartão: fatura em aberto',
                        icon: Icons.account_balance_wallet_rounded,
                        iconGradient: const [
                          AppColors.deepBlueDark,
                          AppColors.primary,
                          AppColors.accent,
                        ],
                        onBack: () => Navigator.pop(ctx),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: const LinearGradient(
                              colors: [Color(0xFFE65100), Color(0xFFFF7043), AppColors.logoOrange],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFE65100).withValues(alpha: 0.35),
                                blurRadius: 14,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: FilledButton.icon(
                            onPressed: widget.profile.hasActiveLicense
                                ? () => _openDashboardPdfStyleSheet(
                                      ctx,
                                      rangeStart,
                                      rangeEnd,
                                      cachedDocs: docs,
                                      openingBalanceHint: openingTotal,
                                    )
                                : () => mostrarAvisoSeLicencaInativa(ctx, widget.profile),
                            icon: const Icon(Icons.picture_as_pdf_rounded, size: 22),
                            label: const Text('Exportar PDF (período do painel)'),
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(50),
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: accountsLoading
                            ? ListView(
                                controller: scrollController,
                                padding:
                                    const EdgeInsets.fromLTRB(20, 8, 20, 24),
                                children: [
                                  for (var i = 0; i < 4; i++)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: Container(
                                        height: 64,
                                        decoration: BoxDecoration(
                                          color: Colors.grey.shade200,
                                          borderRadius: BorderRadius.circular(14),
                                        ),
                                      ),
                                    ),
                                  Text(
                                    'Carregando suas contas…',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600),
                                  ),
                                ],
                              )
                            : accounts.isEmpty
                            ? ListView(
                                controller: scrollController,
                                padding:
                                    const EdgeInsets.fromLTRB(20, 8, 20, 24),
                                children: [
                                  Text(
                                    'Cadastre contas em Financeiro → Bancos e cartões.',
                                    style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.grey.shade700,
                                        height: 1.35),
                                  ),
                                  if (widget.onNavigateTo != null) ...[
                                    const SizedBox(height: 12),
                                    FilledButton.icon(
                                      onPressed: () {
                                        Navigator.pop(ctx);
                                        widget.onNavigateTo!(1);
                                      },
                                      icon:
                                          const Icon(Icons.open_in_new_rounded),
                                      label: const Text('Abrir Financeiro'),
                                    ),
                                  ],
                                ],
                              )
                            : ListView.builder(
                                controller: scrollController,
                                padding: EdgeInsets.fromLTRB(16, 0, 16,
                                    16 + MediaQuery.paddingOf(context).bottom),
                                itemCount: accounts.length + trailingSaldoTiles,
                                itemBuilder: (_, i) {
                                  if (i >= accounts.length) {
                                    final idx = i - accounts.length;
                                    if (showOrphanOpening && idx == 0) {
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 12),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                                color: Colors.amber.shade300),
                                            color: Colors.amber.shade50,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.info_outline_rounded,
                                                  color: Colors.amber.shade900,
                                                  size: 22),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Saldo de abertura sem conta',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: 14,
                                                        color: Colors
                                                            .grey.shade900,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Parte do saldo de abertura veio de lançamentos antigos sem banco/cartão vinculado. '
                                                      'Atribua conta nesses lançamentos no Financeiro para o total por banco fechar com o saldo acumulado.',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          height: 1.35,
                                                          color: Colors
                                                              .grey.shade800),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      CurrencyFormats.formatBRL(
                                                          orphanOpening),
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: 15,
                                                        color: orphanOpening >=
                                                                0
                                                            ? AppColors
                                                                .saldoPositive
                                                            : AppColors
                                                                .saldoNegative,
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
                                    if (showPeriodOrphan &&
                                        idx == (showOrphanOpening ? 1 : 0)) {
                                      return Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 10),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 12),
                                          decoration: BoxDecoration(
                                            borderRadius:
                                                BorderRadius.circular(16),
                                            border: Border.all(
                                                color: Colors.blue.shade200),
                                            color: Colors.blue.shade50,
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Icon(Icons.link_off_rounded,
                                                  color: Colors.blue.shade900,
                                                  size: 22),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      'Período sem conta vinculada',
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: 14,
                                                        color: Colors
                                                            .grey.shade900,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'Há receitas ou despesas pagas neste período sem banco/cartão. '
                                                      'Esse valor entra no «Saldo (acum.)» do painel e não aparece nas linhas acima até você atribuir conta.',
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          height: 1.35,
                                                          color: Colors
                                                              .grey.shade800),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      CurrencyFormats.formatBRL(
                                                          periodOrphan),
                                                      style: TextStyle(
                                                        fontWeight:
                                                            FontWeight.w900,
                                                        fontSize: 15,
                                                        color: periodOrphan >= 0
                                                            ? AppColors
                                                                .saldoPositive
                                                            : AppColors
                                                                .saldoNegative,
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
                                    return const SizedBox.shrink();
                                  }
                                  final a = accounts[i];
                                  final p = a.preset;
                                  final c1 = p?.color1 ?? AppColors.primary;
                                  final c2 = p?.color2 ?? AppColors.primary;
                                  final net = mergedById[a.id] ?? 0;
                                  final isCard = a.isCreditCardProduct;
                                  final fatura = faturaByCard[a.id] ?? 0;
                                  final displayAmount = isCard ? fatura : net;
                                  final pendingOnCard = isCard && fatura > 0.0001;
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 12),
                                    child: FinancePremiumAccountCard(
                                      leading: Container(
                                        width: 48,
                                        height: 48,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(14),
                                          gradient: LinearGradient(
                                            colors: [c1, c2],
                                            begin: Alignment.topLeft,
                                            end: Alignment.bottomRight,
                                          ),
                                        ),
                                        alignment: Alignment.center,
                                        child: FinanceBankBrandThumb(
                                          preset: p,
                                          size: 36,
                                          onBrandGradient: true,
                                          fallbackIcon: p?.icon ?? Icons.account_balance_wallet_rounded,
                                        ),
                                      ),
                                      title: a.displayName,
                                      subtitle: isCard
                                          ? (pendingOnCard
                                              ? 'Cartão · fatura em aberto'
                                              : 'Cartão · sem lançamentos na fatura')
                                          : a.productTypeLabel,
                                      balanceText:
                                          CurrencyFormats.formatBRL(displayAmount),
                                      balanceColor: isCard
                                          ? AppColors.financeDespesa
                                          : (net >= 0
                                              ? AppColors.saldoPositive
                                              : AppColors.saldoNegative),
                                      gradient: [c1, c2],
                                      onTap: () async {
                                        if (isCard) {
                                          _openDashboardCreditCardFaturaSheet(
                                            ctx,
                                            a,
                                            accounts,
                                          );
                                          return;
                                        }
                                        final from = DateTime(rangeStart.year,
                                            rangeStart.month, rangeStart.day);
                                        final to = DateTime(
                                            rangeEnd.year,
                                            rangeEnd.month,
                                            rangeEnd.day,
                                            23,
                                            59,
                                            59);
                                        await showModalBottomSheet<void>(
                                          context: ctx,
                                          isScrollControlled: true,
                                          useSafeArea: true,
                                          backgroundColor: Colors.white,
                                          builder: (_) => FinanceInsightSheet(
                                            uid: _userFsId,
                                            initialScope:
                                                FinanceInsightScope.balance,
                                            initialFrom: from,
                                            initialTo: to,
                                            statusFilter: 'paid',
                                            search: '',
                                            financeAccountFilterId: a.id,
                                            financeAccountFilterLabel:
                                                a.displayName,
                                            openingBalanceHint:
                                                openingById[a.id],
                                            openingByAccountHint: openingById,
                                            onEdit:
                                                (docId, current, type) async {
                                              final e =
                                                  Map<String, dynamic>.from(
                                                      current);
                                              e['id'] = docId;
                                              if (type == 'income') {
                                                await _editarReceitaDashboard(
                                                    context, e);
                                              } else {
                                                await _editarLancamentoDashboard(
                                                    context, e);
                                              }
                                            },
                                            onDelete: (docId) =>
                                                _excluirLancamentoDashboard(
                                                    context, docId),
                                          ),
                                        );
                                      },
                                      trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Column(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(
                                                isCard ? 'Ver fatura' : 'Gráficos',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  color: isCard
                                                      ? AppColors.financeDespesa
                                                      : AppColors.primary,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ],
                                          ),
                                          if (!isCard && widget.onNavigateTo != null)
                                            IconButton(
                                              tooltip: 'Ver lançamentos desta conta no Financeiro',
                                              onPressed: () {
                                                FinanceShellNavigation.requestOpenFinanceiro(accountId: a.id);
                                                Navigator.pop(ctx);
                                                widget.onNavigateTo!(1);
                                              },
                                              icon: const Icon(Icons.receipt_long_rounded, color: AppColors.primary, size: 22),
                                            ),
                                          if (!isCard)
                                            IconButton(
                                              tooltip: 'Exportar PDF desta conta',
                                              onPressed: widget.profile.hasActiveLicense
                                                  ? () => _openDashboardPdfStyleSheet(
                                                        ctx,
                                                        rangeStart,
                                                        rangeEnd,
                                                        financeAccountId: a.id,
                                                        cachedDocs: docs,
                                                        openingBalanceHint: openingById[a.id] ?? 0.0,
                                                      )
                                                  : () => mostrarAvisoSeLicencaInativa(ctx, widget.profile),
                                              icon: const Icon(Icons.picture_as_pdf_outlined, color: Color(0xFFE65100), size: 22),
                                            ),
                                          Icon(Icons.chevron_right_rounded, color: Colors.grey.shade500),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  );
                    },
                  );
                },
              );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  bool _dashTxnPaidEffectiveInPeriod(
      Map<String, dynamic> d, DateTime rangeStart, DateTime rangeEnd) {
    if ((d['status'] ?? 'paid').toString() != 'paid') return false;
    final effectiveDate = FinanceLineOpening.effectiveDateTimeFromMap(d);
    if (effectiveDate == null) return false;
    final rs = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final re =
        DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day, 23, 59, 59);
    return !effectiveDate.isBefore(rs) && !effectiveDate.isAfter(re);
  }

  int _dashSortMsForPdf(Map<String, dynamic> d) {
    final ts = d['date'];
    if (ts is Timestamp) return ts.toDate().millisecondsSinceEpoch;
    if (ts is DateTime) return ts.millisecondsSinceEpoch;
    return 0;
  }

  /// PDF financeiro: Extrato Super Premium (mesmo modelo do Módulo Financeiro e Relatórios).
  Future<void> _exportDashboardFinancePdf(
    BuildContext context,
    DateTime rangeStart,
    DateTime rangeEnd, {
    String? financeAccountId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? cachedDocs,
    double? openingBalanceHint,
  }) async {
    if (!widget.profile.hasActiveLicense) {
      if (context.mounted)
        mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final f = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final tEnd =
        DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day, 23, 59, 59);
    try {
      final accounts = await FinanceAccountsService().listOnce(_userFsId);

      // Caminho rápido: reutiliza docs já carregados na tela (Web/Android sem nova leitura massiva).
      List<QueryDocumentSnapshot<Map<String, dynamic>>> sourceDocs =
          cachedDocs ?? const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
      if (sourceDocs.isEmpty) {
        final txCol = FirebaseFirestore.instance
            .collection('users')
            .doc(_userFsId)
            .collection('transactions');
        Query<Map<String, dynamic>> qByDate = txCol
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(f))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(tEnd))
            .orderBy('date', descending: false);
        Query<Map<String, dynamic>> qByPaidAt = txCol
            .where('status', isEqualTo: 'paid')
            .where('paidAt', isGreaterThanOrEqualTo: Timestamp.fromDate(f))
            .where('paidAt', isLessThanOrEqualTo: Timestamp.fromDate(tEnd))
            .orderBy('paidAt', descending: false);

        if (financeAccountId != null && financeAccountId.isNotEmpty) {
          qByDate =
              qByDate.where('financeAccountId', isEqualTo: financeAccountId);
          qByPaidAt =
              qByPaidAt.where('financeAccountId', isEqualTo: financeAccountId);
        }

        final docsByDate = await firestoreQueryCollectDocumentsBatched(qByDate);
        final docsByPaidAt =
            await firestoreQueryCollectDocumentsBatched(qByPaidAt);
        final mergedById =
            <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
        for (final doc in docsByDate) {
          mergedById[doc.id] = doc;
        }
        for (final doc in docsByPaidAt) {
          mergedById[doc.id] = doc;
        }
        sourceDocs = mergedById.values.toList();
      }

      final periodDocs = sourceDocs.where((doc) {
        final d = doc.data();
        if (financeAccountId != null && financeAccountId.isNotEmpty) {
          final aid = (d['financeAccountId'] ?? '').toString().trim();
          if (aid != financeAccountId) return false;
        }
        if (!_dashTxnPaidEffectiveInPeriod(d, rangeStart, rangeEnd))
          return false;
        return true;
      }).toList();
      if (periodDocs.isEmpty) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text('Nenhum lançamento pago no período para exportar.')),
          );
        }
        return;
      }
      final saldoAbertura = openingBalanceHint ??
          ((financeAccountId == null || financeAccountId.isEmpty)
              ? _openingSaldoTotalBefore(sourceDocs, f)
              : (_openingNetByFinanceAccountBefore(
                      sourceDocs, f)[financeAccountId] ??
                  0.0));
      double totalIncome = 0, totalExpense = 0;
      for (final doc in periodDocs) {
        final d = doc.data();
        final amount = (d['amount'] ?? 0).toDouble();
        if (d['type'] == 'income') totalIncome += amount;
        if (d['type'] == 'expense') totalExpense += amount.abs();
      }
      String? suffix;
      if (financeAccountId != null && financeAccountId.isNotEmpty) {
        for (final a in accounts) {
          if (a.id == financeAccountId) {
            var s = a.displayName
                .replaceAll(RegExp(r'[<>:"/\\|?*\n\r]'), '_')
                .trim();
            if (s.isEmpty) s = 'conta';
            suffix = s.length > 48 ? s.substring(0, 48) : s;
            break;
          }
        }
      }
      final periodo =
          '${DateTimeFormats.dateBR.format(f)} a ${DateTimeFormats.dateBR.format(tEnd)}';
      String dataStr(dynamic ts) {
        if (ts == null) return '';
        if (ts is Timestamp) return DateTimeFormats.dateBR.format(ts.toDate());
        return '';
      }

      final sorted = List<QueryDocumentSnapshot<Map<String, dynamic>>>.from(
          periodDocs)
        ..sort((a, b) =>
            _dashSortMsForPdf(a.data()).compareTo(_dashSortMsForPdf(b.data())));
      final txRows = <Map<String, dynamic>>[];
      for (final doc in sorted) {
        final e = doc.data();
        final isIncome = (e['type'] ?? 'expense').toString() == 'income';
        final cat = (e['category'] ?? '').toString().trim();
        final desc = (e['description'] ?? '').toString().trim();
        final rawDesc = (cat.isNotEmpty ? 'Categoria: $cat' : '') +
            (cat.isNotEmpty && desc.isNotEmpty ? ' — ' : '') +
            (desc.isNotEmpty
                ? 'Descrição: $desc'
                : (cat.isEmpty ? (isIncome ? 'Receita' : 'Despesa') : ''));
        final descricao = rawDesc.trim().isEmpty
            ? (isIncome ? 'Receita' : 'Despesa')
            : RelatorioService.sanitizeForReport(rawDesc);
        final tituloLinha =
            desc.isNotEmpty ? desc : (isIncome ? 'Receita' : 'Despesa');
        txRows.add({
          'sortMs': _dashSortMsForPdf(e),
          'data': dataStr(e['date']),
          'categoria': cat,
          'titulo': tituloLinha,
          'descricao': descricao,
          'tipo': isIncome ? 'receita' : 'despesa',
          'valor': ((e['amount'] ?? 0) as num).toDouble(),
        });
      }
      final filenameBase = RelatorioService.reportFilenameFromPeriod(
        'despesa_receita',
        f,
        tEnd,
        suffix != null && suffix.isNotEmpty ? '— $suffix' : null,
      );
      var contaLabel = 'Todas as contas';
      if (financeAccountId != null && financeAccountId.isNotEmpty) {
        for (final a in accounts) {
          if (a.id == financeAccountId) {
            contaLabel = a.displayName;
            break;
          }
        }
      }
      final logo = await RelatorioService.loadPdfLogoBytesOnce();
      final bytes = await gerarPdfFinanceiroSuperExtrato(
        transacoes: txRows,
        nomeUsuario: widget.profile.name,
        conta: contaLabel,
        periodo: periodo,
        saldoAbertura: saldoAbertura,
        totalReceitas: totalIncome,
        totalDespesas: totalExpense,
        logoPngBytes: logo,
      );
      if (!context.mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) =>
              ReportPreviewScreen(bytes: bytes, filename: filenameBase),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao exportar PDF: $e'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _openDashboardPdfStyleSheet(
    BuildContext context,
    DateTime rangeStart,
    DateTime rangeEnd, {
    String? financeAccountId,
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? cachedDocs,
    double? openingBalanceHint,
  }) async {
    await _exportDashboardFinancePdf(
      context,
      rangeStart,
      rangeEnd,
      financeAccountId: financeAccountId,
      cachedDocs: cachedDocs,
      openingBalanceHint: openingBalanceHint,
    );
  }

  static String _txDateTimeStr(Map<String, dynamic> e) {
    final instant = FinanceFaturaTransactionSort.effectiveInstant(e);
    if (instant != null) return DateTimeFormats.formatTimeOnly(instant);
    return _txDateStr(e['date']);
  }

  static String _txDateStr(dynamic v) {
    if (v == null) return '—';
    if (v is Timestamp) return DateFormat('dd/MM/yyyy').format(v.toDate());
    if (v is DateTime) return DateFormat('dd/MM/yyyy').format(v);
    return v.toString();
  }

  /// Confirma pagamento/recebimento pendente: sheet premium (data, banco, comprovante).
  Future<void> _confirmarLancamentoPendenteDashboard(
      BuildContext context, String docId) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (docId.isEmpty) return;
    final txRef = FirebaseFirestore.instance
        .collection('users')
        .doc(_userFsId)
        .collection('transactions')
        .doc(docId);
    final preSnap = await txRef.get();
    if (!preSnap.exists) return;
    final preData = preSnap.data() ?? {};
    final txType = (preData['type'] ?? 'expense').toString();
    final isIncome = txType == 'income';
    final rawAid = (preData['financeAccountId'] ?? '').toString().trim();
    final financeAccounts = await FinanceAccountsService().listOnce(_userFsId);
    if (!context.mounted) return;

    final result = await showFinanceConfirmPaymentSheet(
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
    if (result == null || !context.mounted) return;

    try {
      await commitFinanceConfirmPayment(
        txRef: txRef,
        uid: widget.uid,
        result: result,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(isIncome ? 'Recebimento confirmado.' : 'Pagamento confirmado.'),
        behavior: SnackBarBehavior.floating,
      ));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao confirmar: ${e.toString().split('\n').first}'),
        backgroundColor: AppColors.error,
      ));
    }
  }

  Future<void> _confirmarPagamentoDashboard(
      BuildContext context, String docId) =>
      _confirmarLancamentoPendenteDashboard(context, docId);


  /// Abre sheet com receitas pendentes (todas, sem filtro). Inclui modo Selecionar e excluir em lote.
  Future<void> _abrirListaReceitasPendentes(
      BuildContext context, List<Map<String, dynamic>> listPendentes) async {
    const blueLight = Color(0xFF0EA5E9);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollController) => _DashboardPendingListSheetContent(
          title: 'Receitas pendentes',
          subtitle: 'Horário · use Ordenar abaixo',
          iconColor: blueLight,
          list: listPendentes,
          scrollController: scrollController,
          emptyMessage: 'Nenhuma receita pendente',
          buildItem: (c, e,
                  {selectionMode = false,
                  isSelected = false,
                  onToggleSelect}) =>
              _buildReceitaPendenteListItem(c, e,
                  selectionMode: selectionMode,
                  isSelected: isSelected,
                  onToggleSelect: onToggleSelect),
          onDeleteBatch: (ids) async {
            await _excluirLancamentoBatchDashboard(context, ids);
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  /// Item da lista de receitas pendentes (quadro azul). Suporta modo seleção (checkbox) e botão Excluir visível.
  Widget _buildReceitaPendenteListItem(
    BuildContext context,
    Map<String, dynamic> e, {
    bool selectionMode = false,
    bool isSelected = false,
    VoidCallback? onToggleSelect,
  }) {
    const blueLight = Color(0xFF0EA5E9);
    final amount = (e['amount'] ?? 0).toDouble().abs();
    final cat = (e['category'] ?? '').toString().trim();
    final desc = (e['description'] ?? e['descricao'] ?? '').toString().trim();
    final dataStr = _txDateTimeStr(e);
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
              Checkbox(
                  value: isSelected,
                  onChanged: (_) => onToggleSelect?.call(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
              const SizedBox(width: 8),
            ],
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: blueLight.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(Icons.arrow_downward_rounded,
                  color: blueLight, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Categoria: ${cat.isNotEmpty ? cat : 'Receita'}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A237E)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text('Descrição: ${desc.isNotEmpty ? desc : '—'}',
                      style: TextStyle(
                          fontSize: 13,
                          color: desc.isEmpty
                              ? Colors.grey
                              : const Color(0xFF1A237E)),
                      maxLines: 5,
                      overflow: TextOverflow.visible),
                  Text(dataStr,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (!selectionMode)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                padding: EdgeInsets.zero,
                onSelected: (v) {
                  if (v == 'editar')
                    _editarReceitaDashboard(context, e);
                  else if (v == 'anexo' && hasReceiptView)
                    mostrarComprovanteReceipt(context, receipt);
                  else if (v == 'anexar')
                    _attachReceiptDashboard(context, docId);
                  else if (v == 'excluir')
                    _excluirLancamentoDashboard(context, docId);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'editar',
                      child: ListTile(
                          title: Text('Editar'),
                          leading: Icon(Icons.edit_rounded),
                          dense: true)),
                  const PopupMenuItem(
                      value: 'anexo',
                      child: ListTile(
                          title: Text('Ver anexo'),
                          leading: Icon(Icons.visibility_rounded),
                          dense: true)),
                  const PopupMenuItem(
                      value: 'anexar',
                      child: ListTile(
                          title: Text('Anexar comprovante'),
                          leading: Icon(Icons.attach_file_rounded),
                          dense: true)),
                  const PopupMenuItem(
                      value: 'excluir',
                      child: ListTile(
                          title: Text('Remover'),
                          leading: Icon(Icons.delete_outline_rounded,
                              color: AppColors.error),
                          dense: true)),
                ],
              ),
            Flexible(
                child: Text(CurrencyFormats.formatBRL(amount),
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: blueLight),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
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
                  onPressed: () =>
                      _confirmarRecebimentoDashboard(context, docId),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Confirmar recebimento',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      minimumSize: const Size(48, 48),
                      tapTargetSize: MaterialTapTargetSize.padded,
                      backgroundColor: AppColors.success.withOpacity(0.15),
                      foregroundColor: AppColors.success),
                ),
                OutlinedButton.icon(
                  onPressed: () => _excluirLancamentoDashboard(context, docId),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Excluir',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error.withOpacity(0.5)),
                      minimumSize: const Size(48, 48),
                      tapTargetSize: MaterialTapTargetSize.padded),
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
      decoration: BoxDecoration(
          color: blueLight.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: blueLight.withOpacity(0.2))),
      child: content,
    );
    if (selectionMode && onToggleSelect != null)
      return InkWell(
          onTap: onToggleSelect,
          borderRadius: BorderRadius.circular(16),
          child: container);
    return container;
  }

  Future<void> _confirmarRecebimentoDashboard(
      BuildContext context, String docId) =>
      _confirmarLancamentoPendenteDashboard(context, docId);

  /// Abre sheet só com despesas pendentes (todas, sem filtro). Inclui modo Selecionar e excluir em lote.
  Future<void> _abrirListaDespesasPendentes(
      BuildContext context, List<Map<String, dynamic>> listPendentes) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollController) => _DashboardPendingListSheetContent(
          title: 'Despesas pendentes',
          subtitle: 'Horário · use Ordenar abaixo',
          iconColor: AppColors.logoOrange,
          list: listPendentes,
          scrollController: scrollController,
          emptyMessage: 'Nenhuma despesa pendente',
          buildItem: (c, e,
                  {selectionMode = false,
                  isSelected = false,
                  onToggleSelect}) =>
              _buildDespesaPendenteListItem(c, e,
                  selectionMode: selectionMode,
                  isSelected: isSelected,
                  onToggleSelect: onToggleSelect),
          onDeleteBatch: (ids) async {
            await _excluirLancamentoBatchDashboard(context, ids);
            if (ctx.mounted) Navigator.pop(ctx);
          },
        ),
      ),
    );
  }

  /// Item da lista de despesas pendentes (quadro laranja): Ver comprovantes, Confirmar pagamento, Editar, Remover.
  /// Item da lista de despesas pendentes (quadro laranja). Suporta modo seleção (checkbox) e botão Excluir visível.
  Widget _buildDespesaPendenteListItem(
    BuildContext context,
    Map<String, dynamic> e, {
    bool selectionMode = false,
    bool isSelected = false,
    VoidCallback? onToggleSelect,
  }) {
    final amount = (e['amount'] ?? 0).toDouble().abs();
    final cat = (e['category'] ?? '').toString().trim();
    final desc = (e['description'] ?? e['descricao'] ?? '').toString().trim();
    final dataStr = _txDateTimeStr(e);
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
              Checkbox(
                  value: isSelected,
                  onChanged: (_) => onToggleSelect?.call(),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
              const SizedBox(width: 8),
            ],
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.arrow_upward_rounded,
                  color: AppColors.error, size: 24),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Categoria: ${cat.isNotEmpty ? cat : 'Despesa'}',
                      style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1A237E)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  Text('Descrição: ${desc.isNotEmpty ? desc : '—'}',
                      style: TextStyle(
                          fontSize: 13,
                          color: desc.isEmpty
                              ? Colors.grey
                              : const Color(0xFF1A237E)),
                      maxLines: 5,
                      overflow: TextOverflow.visible),
                  Text(dataStr,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey.shade600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (!selectionMode)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_rounded),
                padding: EdgeInsets.zero,
                onSelected: (v) {
                  if (v == 'editar')
                    _editarLancamentoDashboard(context, e);
                  else if (v == 'anexo' && hasReceiptView)
                    mostrarComprovanteReceipt(context, receipt);
                  else if (v == 'anexar')
                    _attachReceiptDashboard(context, docId);
                  else if (v == 'excluir')
                    _excluirLancamentoDashboard(context, docId);
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                      value: 'editar',
                      child: ListTile(
                          title: Text('Editar'),
                          leading: Icon(Icons.edit_rounded),
                          dense: true)),
                  const PopupMenuItem(
                      value: 'anexo',
                      child: ListTile(
                          title: Text('Ver anexo'),
                          leading: Icon(Icons.visibility_rounded),
                          dense: true)),
                  const PopupMenuItem(
                      value: 'anexar',
                      child: ListTile(
                          title: Text('Anexar comprovante'),
                          leading: Icon(Icons.attach_file_rounded),
                          dense: true)),
                  const PopupMenuItem(
                      value: 'excluir',
                      child: ListTile(
                          title: Text('Remover'),
                          leading: Icon(Icons.delete_outline_rounded,
                              color: AppColors.error),
                          dense: true)),
                ],
              ),
            Flexible(
                child: Text(CurrencyFormats.formatBRL(amount),
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: AppColors.error),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis)),
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
                  onPressed: () => _confirmarPagamentoDashboard(context, docId),
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Confirmar pagamento',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      minimumSize: const Size(48, 48),
                      tapTargetSize: MaterialTapTargetSize.padded,
                      backgroundColor: AppColors.success.withOpacity(0.15),
                      foregroundColor: AppColors.success),
                ),
                OutlinedButton.icon(
                  onPressed: () => _excluirLancamentoDashboard(context, docId),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Excluir',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: BorderSide(color: AppColors.error.withOpacity(0.5)),
                      minimumSize: const Size(48, 48),
                      tapTargetSize: MaterialTapTargetSize.padded),
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
      decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.error.withOpacity(0.15))),
      child: content,
    );
    if (selectionMode && onToggleSelect != null)
      return InkWell(
          onTap: onToggleSelect,
          borderRadius: BorderRadius.circular(16),
          child: container);
    return container;
  }

  /// Edita lançamento no painel — mesmo modal premium do módulo Financeiro.
  Future<void> _editarLancamentoDashboard(
      BuildContext context, Map<String, dynamic> e) async {
    await _editarTransacaoPainel(context, e, type: 'expense');
  }

  /// Edita receita no painel — mesmo modal premium do módulo Financeiro.
  Future<void> _editarReceitaDashboard(
      BuildContext context, Map<String, dynamic> e) async {
    await _editarTransacaoPainel(context, e, type: 'income');
  }

  Future<void> _editarTransacaoPainel(
    BuildContext context,
    Map<String, dynamic> e, {
    required String type,
  }) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final docId = (e['id'] ?? '').toString();
    if (docId.isEmpty) return;
    final pairId = (e['transferPairId'] ?? '').toString().trim();
    if (pairId.isNotEmpty) {
      final accounts = await FinanceAccountsService().listOnce(_userFsId);
      if (!context.mounted) return;
      final saved = await FinanceTransferBottomSheet.showEdit(
        context,
        uid: _userFsId,
        profile: widget.profile,
        pairId: pairId,
        accounts: accounts,
        logModulo: 'Dashboard',
      );
      if (saved && mounted) {
        setState(() {});
        FinanceTransactionsHub.notifyMutated(uid: _userFsId);
      }
      return;
    }
    final saved = await showFinanceTransactionEditDialog(
      context: context,
      uid: _userFsId,
      profile: widget.profile,
      docId: docId,
      current: e,
      type: type,
      logModulo: 'Dashboard',
    );
    if (saved && mounted) {
      setState(() {});
      FinanceTransactionsHub.notifyMutated(uid: _userFsId);
    }
  }

  /// Anexa comprovante a um lançamento pelo painel (igual ao módulo Financeiro).
  Future<void> _attachReceiptDashboard(
      BuildContext context, String docId) async {
    if (!widget.profile.temAcessoPremium) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    final picked = await ReceiptAttachmentUtils.pickValidated(context);
    if (picked == null) return;
    try {
      await TransactionSaveService.attachReceiptToTransaction(
        uid: widget.uid,
        docId: docId,
        bytes: picked.bytes,
        name: picked.name,
        mime: picked.mime,
        context: context.mounted ? context : null,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Erro: $e')));
      }
    }
  }

  /// Exclui lançamento após confirmação.
  Future<void> _excluirLancamentoDashboard(
      BuildContext context, String docId) async {
    if (docId.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamento'),
        content: const Text('Deseja realmente excluir este lançamento?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(_userFsId)
          .collection('transactions')
          .doc(docId)
          .delete();
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lançamento excluído.')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Erro ao excluir: ${e.toString().split('\n').first}'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  /// Exclui vários lançamentos no painel (uma confirmação, depois exclui em lote). Não faz pop do sheet — quem chama pode dar pop após await.
  Future<void> _excluirLancamentoBatchDashboard(
      BuildContext context, List<String> docIds) async {
    if (docIds.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir lançamentos?'),
        content: Text(
            '${docIds.length} lançamento(s) serão excluídos. Esta ação não pode ser desfeita.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Excluir')),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    int deleted = 0;
    for (final id in docIds) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_userFsId)
            .collection('transactions')
            .doc(id)
            .delete();
        deleted++;
      } catch (_) {}
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$deleted lançamento(s) excluído(s).')));
    }
  }

  /// Início/fim da query de `date` para gráficos (barras, donut, trecho diário da linha).
  /// Saldo de abertura da linha vem de [finance_month_buckets] + query parcial em `effectiveDate` (escala).
  (DateTime, DateTime) _dashboardTxQueryBounds(
      DateTime rangeStart, DateTime rangeEnd) {
    final cap = _kDashboardTxGlobalLowerCap;
    DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);
    DateTime endOfDay(DateTime d) =>
        DateTime(d.year, d.month, d.day, 23, 59, 59, 999);

    var qStart = startOfDay(rangeStart);
    final ranges = _rangesForChart();
    for (final r in ranges) {
      final rs = startOfDay(r.$1);
      if (rs.isBefore(qStart)) qStart = rs;
    }
    if (qStart.isBefore(cap)) qStart = cap;

    var qEnd = endOfDay(rangeEnd);
    for (final r in ranges) {
      final re = endOfDay(r.$2);
      if (re.isAfter(qEnd)) qEnd = re;
    }
    return (qStart, qEnd);
  }

  double _legacyOpeningFromDocsForSaldo(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime limiteAnterior,
  ) {
    double saldoAnterior = 0;
    for (final doc in docs) {
      final d = doc.data();
      final ts = d['date'];
      if (ts is! Timestamp) continue;
      final date = ts.toDate();
      final paidAtTs = d['paidAt'];
      final paidAt = paidAtTs is Timestamp ? paidAtTs.toDate() : null;
      final effectiveDate = paidAt ?? date;
      final amount = (d['amount'] ?? 0).toDouble();
      final type = (d['type'] ?? 'expense').toString();
      final isPaid = (d['status'] ?? 'paid').toString() == 'paid';
      if (effectiveDate.isBefore(limiteAnterior)) {
        if (type == 'income' && isPaid) saldoAnterior += amount;
        if (type != 'income' && isPaid) saldoAnterior -= amount.abs();
      }
    }
    return saldoAnterior;
  }

  static int _fingerprintFinanceBuckets(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var h = 0;
    for (final d in docs) {
      final m = d.data();
      final net = (m['netPaid'] as num?)?.toDouble() ?? 0.0;
      h = Object.hash(h, d.id, net);
    }
    return h;
  }

  static int _fingerprintFinanceChartTx(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    var h = docs.length;
    for (final d in docs) {
      final m = d.data();
      h = Object.hash(
        h,
        d.id,
        m['effectiveDate'],
        m['paidAt'],
        m['date'],
        m['status'],
        m['type'],
        m['amount'],
      );
    }
    return h;
  }

  /// Mesmo resultado que [_openingSaldoAggregated], mas reutiliza o [Future] se os snapshots não mudaram.
  Future<double> _openingSaldoAggregatedMemo(
    DateTime limiteAnterior,
    String partialKey,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> bucketDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> chartDocs,
  ) {
    final key = Object.hash(
      widget.uid,
      limiteAnterior.millisecondsSinceEpoch,
      partialKey,
      _fingerprintFinanceBuckets(bucketDocs),
      _fingerprintFinanceChartTx(chartDocs),
    );
    if (_dashboardOpeningMemoKey == key &&
        _dashboardOpeningMemoFuture != null) {
      return _dashboardOpeningMemoFuture!;
    }
    _dashboardOpeningMemoKey = key;
    _dashboardOpeningMemoFuture =
        _openingSaldoAggregated(limiteAnterior, bucketDocs, chartDocs);
    return _dashboardOpeningMemoFuture!;
  }

  Future<double> _openingSaldoAggregated(
    DateTime limiteAnterior,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> bucketDocs,
    List<QueryDocumentSnapshot<Map<String, dynamic>>> chartDocs,
  ) async {
    double prefix = 0;
    for (final doc in bucketDocs) {
      prefix += (doc.data()['netPaid'] as num?)?.toDouble() ?? 0;
    }
    final monthStart = FinanceLineOpening.startOfMonthWallLocal(limiteAnterior);
    final t0 = Timestamp.fromDate(monthStart);
    final t1 = Timestamp.fromDate(limiteAnterior);
    final partSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(_userFsId)
        .collection('transactions')
        .where('effectiveDate', isGreaterThanOrEqualTo: t0)
        .where('effectiveDate', isLessThan: t1)
        .get();
    final seen = <String>{};
    double partial = 0;
    for (final doc in partSnap.docs) {
      seen.add(doc.id);
      partial += FinanceLineOpening.openingContribution(doc.data());
    }
    for (final doc in chartDocs) {
      if (seen.contains(doc.id)) continue;
      final d = doc.data();
      if (d['effectiveDate'] != null) continue;
      final ts = d['date'];
      if (ts is! Timestamp) continue;
      final date = ts.toDate();
      if (date.isBefore(monthStart)) continue;
      if (!date.isBefore(limiteAnterior)) continue;
      partial += FinanceLineOpening.openingContribution(d);
    }
    return prefix + partial;
  }

  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _dashboardTransactionsStream(
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final (start, end) = _dashboardTxQueryBounds(rangeStart, rangeEnd);
    return financeTransactionsPeriodDocs(
      uid: _userFsId,
      rangeStart: start,
      rangeEnd: end,
    );
  }

  /// Gráficos financeiros: stream de transações (date + effectiveDate) + agregados mensais.
  Widget _buildMergedFinanceChartsBlock(
      DateTime rangeStart, DateTime rangeEnd) {
    final limiteAnterior =
        DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    final partialKey = FinanceLineOpening.monthKeySaoPaulo(limiteAnterior);

    return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      stream: _dashboardTransactionsStream(rangeStart, rangeEnd),
      builder: (context, txSnap) {
        final docs = txSnap.data ??
            const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(_userFsId)
              .collection('finance_month_buckets')
              .orderBy(FieldPath.documentId)
              .where(FieldPath.documentId, isLessThan: partialKey)
              .snapshots(),
          builder: (context, buckSnap) {
            final bucketDocs = buckSnap.data?.docs ??
                const <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            return FutureBuilder<double>(
              future: _openingSaldoAggregatedMemo(
                  limiteAnterior, partialKey, bucketDocs, docs),
              builder: (context, openSnap) {
                final openingAgg = openSnap.data;
                final opening = openingAgg ??
                    _legacyOpeningFromDocsForSaldo(docs, limiteAnterior);
                if (kDebugMode &&
                    openSnap.connectionState == ConnectionState.done) {
                  final (q0, q1) =
                      _dashboardTxQueryBounds(rangeStart, rangeEnd);
                  developer.Timeline.startSync('dashboard_finance_charts',
                      arguments: {
                        'docCount': docs.length,
                        'bucketCount': bucketDocs.length,
                        'openingSample': opening,
                      });
                  developer.Timeline.finishSync();
                  developer.log(
                    'tx [${q0.toIso8601String()} .. ${q1.toIso8601String()}] → ${docs.length} docs; buckets<$partialKey → ${bucketDocs.length}; opening≈$opening',
                    name: 'controle_total.dashboard',
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    RepaintBoundary(child: _financeBarChartFromDocs(docs)),
                    SizedBox(height: _kDashBlockGap),
                    _buildSectionTitle('Evolução do Saldo'),
                    SizedBox(height: _kDashChartTitleGap),
                    RepaintBoundary(
                      child: _saldoLineChartFromTransactionDocs(
                        docs,
                        rangeStart,
                        rangeEnd,
                        saldoAnteriorOverride: opening,
                      ),
                    ),
                    SizedBox(height: _kDashBlockGap),
                    _buildSectionTitle('Receitas e despesas por categoria'),
                    SizedBox(height: _kDashChartTitleGap),
                    RepaintBoundary(
                      child: _financeCategoryChartsFromTransactionDocs(
                          docs, rangeStart, rangeEnd),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _financeBarChartFromDocs(
      List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) {
    final ranges = _rangesForChart();
    final incomeExpenseByRange = <int, (double, double)>{};
    for (final e in ranges.asMap().entries) {
      final (start, end) = e.value;
      double income = 0, expense = 0;
      for (final doc in docs) {
        final d = doc.data();
        final ts = d['date'];
        if (ts is! Timestamp) continue;
        final date = ts.toDate();
        if (date.isBefore(start) || date.isAfter(end)) continue;
        final amount = (d['amount'] ?? 0).toDouble();
        final type = (d['type'] ?? 'expense').toString();
        if (type == 'income') {
          income += amount;
        } else {
          expense += amount.abs();
        }
      }
      incomeExpenseByRange[e.key] = (income, expense);
    }
    double maxData = 1;
    for (final v in incomeExpenseByRange.values) {
      if (v.$1 > maxData) maxData = v.$1;
      if (v.$2 > maxData) maxData = v.$2;
    }
    const maxY = 100.0;
    final barGroups = incomeExpenseByRange.entries.map((e) {
      final (income, expense) = e.value;
      final scale = maxData > 0 ? maxY / maxData : 1.0;
      return BarChartGroupData(
        x: e.key,
        barRods: [
          BarChartRodData(
            toY: (income * scale).clamp(0.0, maxY),
            color: const Color(0xFF2962FF),
            width: 15,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
          BarChartRodData(
            toY: (expense * scale).clamp(0.0, maxY),
            color: Colors.redAccent,
            width: 15,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
        ],
        showingTooltipIndicators: [],
      );
    }).toList();

    double totalIncome = 0, totalExpense = 0;
    for (final v in incomeExpenseByRange.values) {
      totalIncome += v.$1;
      totalExpense += v.$2;
    }
    return Container(
      height: 250,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: const Color(0xFF2962FF),
                          borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Receitas',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151))),
                      Text(CurrencyFormats.formatBRL(totalIncome),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade600)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Despesas',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF374151))),
                      Text(CurrencyFormats.formatBRL(totalExpense),
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Colors.grey.shade600)),
                    ],
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barGroups: barGroups.isEmpty
                    ? [
                        _makeGroupData(0, 70, 40),
                        _makeGroupData(1, 80, 30),
                        _makeGroupData(2, 60, 50)
                      ]
                    : barGroups,
                titlesData: FlTitlesData(
                  show: true,
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, meta) {
                        if (v.toInt() >= 0 && v.toInt() < ranges.length) {
                          final (s, _) = ranges[v.toInt()];
                          if (_selectedPeriod == 'Mensal' ||
                              _selectedPeriod == 'Anual' ||
                              _selectedPeriod == 'Mês anterior') {
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                DateFormat('MMM', 'pt_BR').format(s),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF374151)),
                              ),
                            );
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              '${s.day}/${s.month}',
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF374151)),
                            ),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                      reservedSize: 28,
                      interval: 1,
                    ),
                  ),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barTouchData: BarTouchData(enabled: false),
              ),
              duration: Duration.zero,
            ),
          ),
        ],
      ),
    );
  }

  /// Gráfico de linha: evolução do saldo acumulado dia a dia (com saldo de abertura).
  /// [saldoAnteriorOverride] quando não null vem de agregados Firestore + parcial em `effectiveDate`.
  Widget _saldoLineChartFromTransactionDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime rangeStart,
    DateTime rangeEnd, {
    double? saldoAnteriorOverride,
  }) {
    final limiteAnterior =
        DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
    double saldoAnterior = 0;
    final byDay = <DateTime, double>{};
    var current = rangeStart;
    while (!current.isAfter(rangeEnd)) {
      byDay[DateTime(current.year, current.month, current.day)] = 0;
      current = current.add(const Duration(days: 1));
    }
    if (saldoAnteriorOverride != null) {
      saldoAnterior = saldoAnteriorOverride;
    } else {
      for (final doc in docs) {
        final d = doc.data();
        final ts = d['date'];
        if (ts is! Timestamp) continue;
        final date = ts.toDate();
        final paidAtTs = d['paidAt'];
        final paidAt = paidAtTs is Timestamp ? paidAtTs.toDate() : null;
        final effectiveDate = paidAt ?? date;
        final amount = (d['amount'] ?? 0).toDouble();
        final type = (d['type'] ?? 'expense').toString();
        final isPaid = (d['status'] ?? 'paid').toString() == 'paid';
        if (effectiveDate.isBefore(limiteAnterior)) {
          if (type == 'income' && isPaid) saldoAnterior += amount;
          if (type != 'income' && isPaid) saldoAnterior -= amount.abs();
        }
      }
    }
    for (final doc in docs) {
      final d = doc.data();
      final ts = d['date'];
      if (ts is! Timestamp) continue;
      final date = ts.toDate();
      final amount = (d['amount'] ?? 0).toDouble();
      final type = (d['type'] ?? 'expense').toString();
      final isPaid = (d['status'] ?? 'paid').toString() == 'paid';
      final dayKey = DateTime(date.year, date.month, date.day);
      if (!byDay.containsKey(dayKey)) continue;
      if (type == 'income') {
        byDay[dayKey] = byDay[dayKey]! + amount;
      } else if (isPaid) {
        byDay[dayKey] = byDay[dayKey]! - amount.abs();
      }
    }
    final sortedDays = byDay.keys.toList()..sort();
    double acum = saldoAnterior;
    final spots = <FlSpot>[];
    for (var i = 0; i < sortedDays.length; i++) {
      acum += byDay[sortedDays[i]]!;
      spots.add(FlSpot(i.toDouble(), acum));
    }
    final maxY = spots.isEmpty
        ? 1.0
        : spots
            .map((s) => s.y)
            .reduce((a, b) => a.abs() > b.abs() ? a : b)
            .abs();
    final minY = spots.isEmpty
        ? 0.0
        : spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final rangeY = (maxY - minY).abs().clamp(1.0, double.infinity);
    return Container(
      height: 220,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: spots.isEmpty
          ? Center(
              child: Text('Sem dados no período',
                  style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600)),
            )
          : LineChart(
              LineChartData(
                minY: minY - rangeY * 0.1,
                maxY: maxY + rangeY * 0.1,
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1A237E),
                    tooltipPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((s) {
                        final idx = s.x.toInt();
                        final day =
                            idx < sortedDays.length ? sortedDays[idx] : null;
                        return LineTooltipItem(
                          '${day != null ? DateFormat('dd/MM').format(day) : ''}\n${CurrencyFormats.formatBRL(s.y)}',
                          const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        );
                      }).toList();
                    },
                  ),
                ),
                gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (v) =>
                        FlLine(color: Colors.grey.shade200)),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 24,
                      interval:
                          (sortedDays.length / 5).clamp(1.0, double.infinity),
                      getTitlesWidget: (v, meta) {
                        final idx = v.toInt();
                        if (idx >= 0 && idx < sortedDays.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                                DateFormat('dd/MM', 'pt_BR')
                                    .format(sortedDays[idx]),
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade400)),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    color: const Color(0xFF2962FF),
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: true),
                    belowBarData: BarAreaData(
                        show: true,
                        color: const Color(0xFF2962FF).withValues(alpha: 0.15)),
                  ),
                ],
              ),
              duration: Duration.zero,
            ),
    );
  }

  Widget _financeCategoryChartsFromTransactionDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    DateTime rangeStart,
    DateTime rangeEnd,
  ) {
    final incomeByCategory = <String, double>{};
    final expenseByCategory = <String, double>{};
    final catMerger = FinanceCategoryMerger();
    for (final doc in docs) {
      final d = doc.data();
      final ts = d['date'];
      if (ts is Timestamp) {
        final date = ts.toDate();
        if (date.isBefore(rangeStart) || date.isAfter(rangeEnd)) continue;
      }
      final raw = (d['category'] ?? '').toString().trim();
      final cat = raw.isEmpty ? 'Outros' : raw;
      final amount = (d['amount'] ?? 0).toDouble().abs();
      final type = (d['type'] ?? 'expense').toString();
      if (type == 'income') {
        catMerger.addAmount(incomeByCategory, cat, amount, emptyLabel: 'Outros');
      } else {
        catMerger.addAmount(expenseByCategory, cat, amount, emptyLabel: 'Outros');
      }
    }
    return FinanceCategoryChartsSuite(
      mode: 'both',
      incomeByCategory: incomeByCategory,
      expenseByCategory: expenseByCategory,
    );
  }

  BarChartGroupData _makeGroupData(int x, double y1, double y2) {
    return BarChartGroupData(
      x: x,
      barRods: [
        BarChartRodData(
            toY: y1,
            color: const Color(0xFF2962FF),
            width: 15,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
        BarChartRodData(
            toY: y2,
            color: Colors.redAccent,
            width: 15,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
      ],
      showingTooltipIndicators: [],
    );
  }

  /// Exclui meta cujo título é "Banco de Horas" do painel inicial (mostrar todas as outras).
  static bool _excluirMetaBancoDeHoras(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final title = ((doc.data()['title'] ?? '') as String).toLowerCase();
    return title.contains('banco de horas');
  }

  Widget _buildGoalProgress() {
    return RepaintBoundary(
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(_userFsId)
            .collection('goals')
            .where('status', isEqualTo: 'active')
            .snapshots(),
        builder: (context, goalSnap) {
          final allGoals = goalSnap.data?.docs ?? [];
          final goals =
              allGoals.where((d) => !_excluirMetaBancoDeHoras(d)).toList();
          if (goals.isEmpty) {
            return _goalPlaceholder();
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: goals.map((goal) => _buildOneGoalCard(goal)).toList(),
          );
        },
      ),
    );
  }

  Widget _buildOneGoalCard(QueryDocumentSnapshot<Map<String, dynamic>> goal) {
    final data = goal.data();
    final title = (data['title'] ?? 'Meta').toString();
    final target = (data['targetAmount'] ?? 0).toDouble();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: goal.reference.collection('contributions').snapshots(),
      builder: (context, contribSnap) {
        double current = 0;
        for (final doc in contribSnap.data?.docs ?? []) {
          current += (doc.data()['amount'] ?? 0).toDouble();
        }
        final progress = target > 0 ? (current / target).clamp(0.0, 1.0) : 0.0;
        final faltam = (target - current).clamp(0.0, double.infinity);
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFF1A237E), Color(0xFF2962FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
            boxShadow: [
              BoxShadow(
                  color: const Color(0xFF2962FF).withOpacity(0.3),
                  blurRadius: 16,
                  offset: const Offset(0, 8))
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Meta: $title',
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                    fontSize: 15),
                softWrap: true,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (progress >= 0.8 && progress < 1.0)
                    Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('Quase lá!',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11)),
                    ),
                  Text('${(progress * 100).round()}%',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 15),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white24,
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
                  minHeight: 10,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Faltam ${CurrencyFormats.formatBRL(faltam)} para atingir o objetivo',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                softWrap: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () =>
                          _registrarAporte(context, goal.reference),
                      icon: const Icon(Icons.add_rounded,
                          size: 18, color: Colors.white),
                      label: const Text('Fazer aporte',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white70),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _verEditarAportes(context, goal, title),
                      icon: const Icon(Icons.list_alt_rounded,
                          size: 18, color: Colors.white),
                      label: const Text('Ver/Editar Aportes',
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white70),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _verEditarAportes(
      BuildContext context,
      QueryDocumentSnapshot<Map<String, dynamic>> goalDoc,
      String goalTitle) async {
    await showGoalContributionsSheet(
      context: context,
      goalDoc: goalDoc,
      goalTitle: goalTitle,
      uid: _userFsId,
      profile: widget.profile,
    );
  }

  Widget _goalPlaceholder() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [Color(0xFF1A237E), Color(0xFF2962FF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
        boxShadow: [
          BoxShadow(
              color: const Color(0xFF2962FF).withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Meta: Reserva de Emergência',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w500)),
              const Text('75%',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 15),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: 0.75,
              backgroundColor: Colors.white24,
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Colors.greenAccent),
              minHeight: 10,
            ),
          ),
          const SizedBox(height: 10),
          const Text('Crie objetivos no módulo Objetivos Financeiros e acompanhe aqui.',
              style: TextStyle(color: Colors.white70, fontSize: 12)),
          if (widget.onNavigateTo != null) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => widget.onNavigateTo!(2),
                icon: const Icon(Icons.add_rounded,
                    size: 20, color: Colors.white),
                label: const Text('Criar objetivo',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w600)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white70),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEscalaStats(List<ScaleEntry> entries, String periodLabel) {
    double hoursDay = 0, hoursNight = 0;
    double valorDiurno = 0, valorNoturno = 0;
    final entriesDiurnas = <ScaleEntry>[];
    final entriesNoturnas = <ScaleEntry>[];
    for (final e in entries) {
      // Igual ao módulo Escalas: inclui lançamentos do dia atual (paid pode ser false até confirmar).
      if (e.isCompromisso) continue;
      hoursDay += e.hoursDay;
      hoursNight += e.hoursNight;
      valorDiurno += e.hoursDay * e.dayRate;
      valorNoturno += e.hoursNight * e.nightRate;
      if (e.hoursDay > 0) entriesDiurnas.add(e);
      if (e.hoursNight > 0) entriesNoturnas.add(e);
    }
    entriesDiurnas.sort((a, b) => b.date.compareTo(a.date));
    entriesNoturnas.sort((a, b) => b.date.compareTo(a.date));
    return Row(
      children: [
        _miniStatCardHoras(
          'Diurnas',
          hoursDay,
          valorDiurno,
          Icons.wb_sunny_rounded,
          Colors.orange,
          entries: entriesDiurnas,
          periodLabel: periodLabel,
          isNoturnas: false,
        ),
        const SizedBox(width: 15),
        _miniStatCardHoras(
          'Noturnas',
          hoursNight,
          valorNoturno,
          Icons.nights_stay_rounded,
          Colors.indigo,
          entries: entriesNoturnas,
          periodLabel: periodLabel,
          isNoturnas: true,
        ),
      ],
    );
  }

  /// Card com horas e valor (R$) — clicável para listar plantões (diurnas/noturnas).
  Widget _miniStatCardHoras(
    String title,
    double horas,
    double valor,
    IconData icon,
    Color color, {
    List<ScaleEntry>? entries,
    String? periodLabel,
    bool isNoturnas = false,
  }) {
    final child = Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, 6))
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          Text('${horas.toStringAsFixed(1)}h',
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1A237E))),
          const SizedBox(height: 4),
          Text(CurrencyFormats.formatBRL(valor),
              style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700, color: color)),
          if (entries != null && periodLabel != null) ...[
            const SizedBox(height: 4),
            Text('Toque para ver',
                style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
          ],
        ],
      ),
    );
    if (entries != null && periodLabel != null) {
      return Expanded(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () =>
                _abrirPlantaoesHoras(context, entries, periodLabel, isNoturnas),
            borderRadius: BorderRadius.circular(20),
            child: child,
          ),
        ),
      );
    }
    return Expanded(child: child);
  }

  /// Gráfico com valores (R$) de horas diurnas e noturnas — padrão GO ou conforme parametrizado.
  /// Plantões no período (exceto compromisso sem valor); não exige mais `paid` só para dados do próprio período.
  Widget _buildEscalaChart(List<ScaleEntry> entries) {
    final filtered = entries.where((e) => !e.isCompromisso).toList();
    final sorted = List<ScaleEntry>.from(filtered)
      ..sort((a, b) => a.date.compareTo(b.date));
    final spotsDiurno = <FlSpot>[];
    final spotsNoturno = <FlSpot>[];
    double maxY = 1.0;
    for (var i = 0; i < sorted.length; i++) {
      final e = sorted[i];
      final vD = e.hoursDay * e.dayRate;
      final vN = e.hoursNight * e.nightRate;
      spotsDiurno.add(FlSpot(i.toDouble(), vD));
      spotsNoturno.add(FlSpot(i.toDouble(), vN));
      if (vD > maxY) maxY = vD;
      if (vN > maxY) maxY = vN;
    }
    if (spotsDiurno.isEmpty && spotsNoturno.isEmpty) {
      spotsDiurno.addAll([const FlSpot(0, 0), const FlSpot(1, 0)]);
      spotsNoturno.addAll([const FlSpot(0, 0), const FlSpot(1, 0)]);
    }
    maxY = maxY.clamp(1.0, double.infinity);
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14.0;
    final leftReserved = (40 * textScale).clamp(40.0, 96.0);
    final chartHeight = (220 * textScale).clamp(220.0, 320.0);

    return Container(
      height: chartHeight,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: Colors.orange,
                          borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 6),
                  Text('Diurnas (R\$)',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700)),
                ],
              ),
              const SizedBox(width: 16),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                          color: Colors.indigo,
                          borderRadius: BorderRadius.circular(4))),
                  const SizedBox(width: 6),
                  Text('Noturnas (R\$)',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: LineChart(
              LineChartData(
                minY: 0,
                maxY: maxY * 1.15,
                gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (v) =>
                        FlLine(color: Colors.grey.shade200)),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: leftReserved,
                    getTitlesWidget: (v, meta) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(
                          CurrencyFormats.formatBRLTight(v),
                          style: TextStyle(
                              fontSize: 9, color: Colors.grey.shade600),
                          maxLines: 1,
                        ),
                      ),
                    ),
                  )),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                      interval: (sorted.length / 4).clamp(1.0, double.infinity),
                      getTitlesWidget: (v, meta) {
                        final idx = v.toInt();
                        if (idx >= 0 && idx < sorted.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(
                                DateFormat('dd/MM', 'pt_BR')
                                    .format(sorted[idx].date),
                                style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey.shade500)),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                lineTouchData: LineTouchData(
                  enabled: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => const Color(0xFF1A237E),
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((s) {
                        final label = s.barIndex == 0 ? 'Diurnas' : 'Noturnas';
                        return LineTooltipItem(
                            '$label\n${CurrencyFormats.formatBRL(s.y)}',
                            const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600));
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spotsDiurno,
                    isCurved: true,
                    color: Colors.orange,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                        show: true,
                        getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                            radius: 3, color: Colors.orange)),
                    belowBarData: BarAreaData(
                        show: true, color: Colors.orange.withOpacity(0.12)),
                  ),
                  LineChartBarData(
                    spots: spotsNoturno,
                    isCurved: true,
                    color: Colors.indigo,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                        show: true,
                        getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                            radius: 3, color: Colors.indigo)),
                    belowBarData: BarAreaData(
                        show: true, color: Colors.indigo.withOpacity(0.12)),
                  ),
                ],
              ),
              duration: const Duration(milliseconds: 350),
            ),
          ),
        ],
      ),
    );
  }

  /// Faixa de aviso teto de horas (só plantões com valor financeiro; teto configurável em Configurações).
  ///
  /// Quando [entriesFromSectionQuery] cobre o mês civil atual, reutiliza os dados (menos um listener em `scales` na web).
  Widget _buildFaixaAvisoTeto192(
    BuildContext context,
    DateTime rangeStart,
    DateTime endPlantoesAFuturo,
    DateTime hoje, {
    List<ScaleEntry>? entriesFromSectionQuery,
    DateTime? escalasSectionStart,
    DateTime? escalasSectionEnd,
    bool forPainelTopo = false,
  }) {
    final monthStart = DateTime(hoje.year, hoje.month, 1);
    final monthEnd = DateTime(hoje.year, hoje.month + 1, 0, 23, 59, 59);
    final msDay = DateTime(monthStart.year, monthStart.month, monthStart.day);
    final meDay = DateTime(monthEnd.year, monthEnd.month, monthEnd.day);

    List<ScaleEntry>? monthFromSection;
    if (entriesFromSectionQuery != null &&
        escalasSectionStart != null &&
        escalasSectionEnd != null &&
        _dateRangeCoversFullCalendarMonth(
            escalasSectionStart, escalasSectionEnd, hoje)) {
      monthFromSection = entriesFromSectionQuery.where((e) {
        final d = DateTime(e.date.year, e.date.month, e.date.day);
        return !d.isBefore(msDay) && !d.isAfter(meDay);
      }).toList();
    }

    return StreamBuilder<ControleTotalConfig>(
      stream: ControleTotalConfigService().watchConfig(_userFsId),
      builder: (context, configSnap) {
        final config = configSnap.data ?? const ControleTotalConfig();
        final tetoHoras = config.tetoHorasMensal > 0
            ? config.tetoHorasMensal
            : ControleTotalConfig.tetoHorasMensalPadrao;

        if (monthFromSection != null) {
          return _faixaTetoHorasMesBody(
            entries: monthFromSection,
            tetoHoras: tetoHoras,
            hoje: hoje,
            monthStart: monthStart,
            forPainelTopo: forPainelTopo,
          );
        }

        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(_userFsId)
              .collection('scales')
              .where('date',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
              .where('date', isLessThanOrEqualTo: Timestamp.fromDate(monthEnd))
              .snapshots(),
          builder: (context, scaleSnap) {
            final entries = _scaleEntriesFromQuerySafe(scaleSnap.data);
            return _faixaTetoHorasMesBody(
              entries: entries,
              tetoHoras: tetoHoras,
              hoje: hoje,
              monthStart: monthStart,
              forPainelTopo: forPainelTopo,
            );
          },
        );
      },
    );
  }

  Widget _faixaTetoHorasMesBody({
    required List<ScaleEntry> entries,
    required double tetoHoras,
    required DateTime hoje,
    required DateTime monthStart,
    bool forPainelTopo = false,
  }) {
    final comValor = entries.where((e) => e.totalValue > 0).toList();
    if (comValor.isEmpty) {
      return const SizedBox.shrink();
    }
    double horasJa = 0;
    double horasPrevisao = 0;
    final hojeNorm = DateTime(hoje.year, hoje.month, hoje.day);
    for (final e in comValor) {
      final h = e.hoursDay + e.hoursNight;
      horasPrevisao += h;
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      if (d.isBefore(hojeNorm) || d.isAtSameMomentAs(hojeNorm)) horasJa += h;
    }
    final passouTeto = horasPrevisao > tetoHoras;
    final tetoInt = tetoHoras.round();
    final diffTeto = tetoHoras - horasPrevisao;
    final jaStr = '${horasJa.toStringAsFixed(1)} h';
    final prevStr = '${horasPrevisao.toStringAsFixed(1)} h';
    final tetoStr = '$tetoInt h';
    final tituloAlerta = forPainelTopo
        ? (passouTeto
            ? 'Controle de horas — acima do teto'
            : 'Controle de horas')
        : (passouTeto
            ? 'Atenção: previsão acima do teto'
            : 'Horas de plantão no mês');
    final rodapeAlerta = passouTeto
        ? 'Revise escalas ou ajuste o teto em Configurações > Horas extras.'
        : (forPainelTopo
            ? 'Resumo do mês atual (plantões com valor). Escalas no ícone do rodapé.'
            : 'Resumo do mês atual (plantões com valor). Toque em Escalas para detalhes.');
    String formatHorasDelta(double horas) {
      final arred = (horas * 10).round() / 10;
      if ((arred - arred.roundToDouble()).abs() < 0.05) {
        return '${arred.round()} h';
      }
      return '${arred.toStringAsFixed(1)} h';
    }

    final String margemTitle;
    final String margemValue;
    final Color margemBg;
    final Color margemFg;
    if (passouTeto) {
      final excedeu = horasPrevisao - tetoHoras;
      margemTitle = 'Acima do teto';
      margemValue = 'Passou ${formatHorasDelta(excedeu)}';
      margemBg = const Color(0xFFFFEBEE);
      margemFg = const Color(0xFFC62828);
    } else if (diffTeto <= 0.05) {
      margemTitle = 'Margem';
      margemValue = 'No teto';
      margemBg = const Color(0xFFE8F5E9);
      margemFg = const Color(0xFF2E7D32);
    } else {
      final h = formatHorasDelta(diffTeto);
      margemTitle = 'Margem';
      margemValue =
          diffTeto >= 0.95 && diffTeto < 1.05 ? 'Falta $h' : 'Faltam $h';
      margemBg = const Color(0xFFE8F5E9);
      margemFg = const Color(0xFF1B5E20);
    }

    Widget metricPill({
      required String title,
      required String value,
      required Color bg,
      required Color fg,
      bool ring = false,
      bool emphasized = false,
    }) {
      return Container(
        constraints: const BoxConstraints(minWidth: 100),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: emphasized
                ? fg.withValues(alpha: 0.75)
                : ring
                    ? fg.withValues(alpha: 0.55)
                    : fg.withValues(alpha: 0.22),
            width: emphasized ? 2.5 : (ring ? 2 : 1),
          ),
          boxShadow: [
            BoxShadow(
              color: fg.withValues(alpha: emphasized ? 0.22 : 0.07),
              blurRadius: emphasized ? 12 : 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title.toUpperCase(),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.85,
                color: fg.withValues(alpha: 0.72),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              value,
              style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w900,
                height: 1.05,
                color: fg,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(top: forPainelTopo ? 0 : 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: passouTeto
                ? [
                    Colors.orange.shade50,
                    Colors.orange.shade100.withValues(alpha: 0.45),
                  ]
                : [
                    AppColors.primary.withValues(alpha: 0.10),
                    Colors.white,
                  ],
          ),
          borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
          border: Border.all(
            width: 1.5,
            color: passouTeto
                ? Colors.orange.shade400
                : AppColors.primary.withValues(alpha: 0.35),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  passouTeto
                      ? Icons.warning_amber_rounded
                      : Icons.schedule_rounded,
                  size: 28,
                  color:
                      passouTeto ? Colors.orange.shade900 : AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tituloAlerta,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.2,
                          color: passouTeto
                              ? Colors.orange.shade900
                              : const Color(0xFF1A237E),
                        ),
                      ),
                      const SizedBox(height: 6),
                      MonthYearResumoHeader(monthStart: monthStart),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                metricPill(
                  title: forPainelTopo ? 'Horas tiradas' : 'Já fez',
                  value: jaStr,
                  bg: passouTeto
                      ? Colors.white.withValues(alpha: 0.92)
                      : const Color(0xFFE8EAF6),
                  fg: const Color(0xFF1A237E),
                ),
                metricPill(
                  title: forPainelTopo ? 'Previsão' : 'Previsão no mês',
                  value: prevStr,
                  bg: passouTeto
                      ? Colors.deepOrange.shade50
                      : const Color(0xFFFFF3E0),
                  fg: const Color(0xFFE65100),
                ),
                metricPill(
                  title: 'Teto',
                  value: tetoStr,
                  bg: passouTeto ? Colors.red.shade50 : const Color(0xFFE3F2FD),
                  fg: const Color(0xFF0D47A1),
                  ring: true,
                ),
                metricPill(
                  title: margemTitle,
                  value: margemValue,
                  bg: margemBg,
                  fg: margemFg,
                  emphasized: true,
                  ring: true,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              rodapeAlerta,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.35,
                color: passouTeto
                    ? Colors.orange.shade900
                    : const Color(0xFF1A237E),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Resolve employerType para um plantão: usa campo salvo ou faz match por label/abbreviation com locations.
  static String _employerTypeForEntry(
      ScaleEntry e, List<ShiftLocation> locations) {
    if (e.employerType != null && e.employerType!.isNotEmpty)
      return e.employerType!;
    final labelBase = (e.label ?? '').trim().toUpperCase();
    final abbr = (e.abbreviation ?? '').trim().toUpperCase();
    if (labelBase.isEmpty && abbr.isEmpty) return 'private';
    for (final loc in locations) {
      final nameBase = ShiftLocation.baseNameFromFull(loc.name).toUpperCase();
      final locAbbr = loc.abbreviation.trim().toUpperCase();
      if (nameBase.isNotEmpty &&
          (labelBase.contains(nameBase) || nameBase.contains(labelBase)))
        return loc.employerType.name;
      if (locAbbr.isNotEmpty &&
          (abbr == locAbbr || labelBase.contains(locAbbr)))
        return loc.employerType.name;
    }
    return 'private';
  }

  /// Quadro por vínculo (Estado / Município / Particular) com total, já tirados e não tirados.
  Widget _buildQuadrosEstadoMunicipioParticular(List<ScaleEntry> entries,
      DateTime hoje, String periodLabel, List<ShiftLocation> locations) {
    final types = ['state', 'municipality', 'private'];
    final labels = {
      'state': 'Estado',
      'municipality': 'Município',
      'private': 'Particular'
    };
    final listByType = <String, List<ScaleEntry>>{};
    final listJaByType = <String, List<ScaleEntry>>{};
    final listNaoByType = <String, List<ScaleEntry>>{};
    for (final t in types) {
      listByType[t] = [];
      listJaByType[t] = [];
      listNaoByType[t] = [];
    }
    for (final e in entries) {
      if (e.isCompromisso) continue;
      final t = _employerTypeForEntry(e, locations);
      if (!listByType.containsKey(t)) listByType[t] = [];
      listByType[t]!.add(e);
      if (e.effectiveJaTiradoParaExibicaoComLocais(hoje, locations)) {
        listJaByType[t]!.add(e);
      } else {
        listNaoByType[t]!.add(e);
      }
    }
    for (final t in types) {
      listJaByType[t]!.sort((a, b) => b.date.compareTo(a.date));
      listNaoByType[t]!.sort((a, b) => a.date.compareTo(b.date));
    }
    final totalPorVinculo =
        listByType.values.fold<int>(0, (s, list) => s + list.length);
    final listTotalByType = <String, List<ScaleEntry>>{};
    final totalByTypeValues = <String, double>{};
    final totalByTypeCounts = <String, int>{};
    final jaByTypeValues = <String, double>{};
    final jaByTypeCounts = <String, int>{};
    final naoByTypeValues = <String, double>{};
    final naoByTypeCounts = <String, int>{};

    for (final t in types) {
      final combined = <ScaleEntry>[];
      combined.addAll(listJaByType[t]!);
      combined.addAll(listNaoByType[t]!);
      combined.sort((a, b) => b.date.compareTo(a.date));
      listTotalByType[t] = combined;
      totalByTypeValues[t] =
          combined.fold<double>(0, (s, e) => s + e.totalValue);
      totalByTypeCounts[t] = combined.length;
      jaByTypeValues[t] =
          listJaByType[t]!.fold<double>(0, (s, e) => s + e.totalValue);
      jaByTypeCounts[t] = listJaByType[t]!.length;
      naoByTypeValues[t] =
          listNaoByType[t]!.fold<double>(0, (s, e) => s + e.totalValue);
      naoByTypeCounts[t] = listNaoByType[t]!.length;
    }

    final sumTotalPeriod = types.fold<double>(
      0,
      (s, t) => s + (totalByTypeValues[t] ?? 0),
    );
    final countTotalPeriod = types.fold<int>(
      0,
      (s, t) => s + (totalByTypeCounts[t] ?? 0),
    );

    // Backward compat: mantém título de total consolidado para abrir modal completo.
    final allJaMerged = <ScaleEntry>[
      for (final t in types) ...listJaByType[t]!,
    ]..sort((a, b) => b.date.compareTo(a.date));
    final allNaoMerged = <ScaleEntry>[
      for (final t in types) ...listNaoByType[t]!,
    ]..sort((a, b) => a.date.compareTo(b.date));

    Widget vinculoBlock(String t) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _abrirPlantoesTotal(
              context, listTotalByType[t]!, periodLabel,
              tipoLabel: labels[t]),
          borderRadius: BorderRadius.circular(16),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 380;
              final valueFont = compact ? 30.0 : 35.0;
              final chipFont = compact ? 15.0 : 16.0;
              return Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                    vertical: compact ? 12 : 14, horizontal: compact ? 10 : 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF1A237E).withValues(alpha: 0.05),
                      const Color(0xFF3949AB).withValues(alpha: 0.03),
                    ],
                  ),
                  border: Border.all(
                      color: const Color(0xFF1A237E).withValues(alpha: 0.10)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${labels[t]} — total',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF1A237E)),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        CurrencyFormats.formatBRL(totalByTypeValues[t] ?? 0),
                        style: TextStyle(
                            fontSize: valueFont,
                            height: 1.0,
                            fontWeight: FontWeight.w900,
                            color: const Color(0xFF1A237E)),
                      ),
                    ),
                    Text(
                      '${totalByTypeCounts[t] ?? 0} plantão(ões)',
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade800),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      onTap: () => _abrirPlantoesJaTirado(
                          context, listJaByType[t]!, periodLabel,
                          tipoLabel: labels[t]),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                            horizontal: compact ? 8 : 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Já tirados: ${jaByTypeCounts[t] ?? 0} · ${CurrencyFormats.formatBRL(jaByTypeValues[t] ?? 0)}',
                          style: TextStyle(
                              fontSize: chipFont,
                              color: Colors.green.shade800,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    InkWell(
                      onTap: () => _abrirPlantoesATirar(
                          context, listNaoByType[t]!, periodLabel,
                          tipoLabel: labels[t]),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                            horizontal: compact ? 8 : 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Não tirados: ${naoByTypeCounts[t] ?? 0} · ${CurrencyFormats.formatBRL(naoByTypeValues[t] ?? 0)}',
                          style: TextStyle(
                              fontSize: chipFont,
                              color: Colors.blue.shade800,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text('Toque para ver lista',
                        style: TextStyle(
                            fontSize: compact ? 10 : 11,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600)),
                  ],
                ),
              );
            },
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 20,
              offset: const Offset(0, 8))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'Por vínculo (Estado / Município / Particular)',
              style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade800),
            ),
          ),
          if (totalPorVinculo == 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('Nenhum plantão por vínculo neste período.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                      fontStyle: FontStyle.italic)),
            ),
          Column(
            children: [
              vinculoBlock('state'),
              const SizedBox(height: 10),
              vinculoBlock('municipality'),
              const SizedBox(height: 10),
              vinculoBlock('private'),
            ],
          ),
          if (totalPorVinculo > 0) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: Colors.grey.shade200),
            const SizedBox(height: 14),
            Text(
              'Total no período (Estado + Município + Particular)',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade800),
            ),
            const SizedBox(height: 4),
            Text(
              'Soma de já tirados + não tirados (inclui Particular) no filtro acima.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF1A237E).withValues(alpha: 0.07),
                    const Color(0xFF3949AB).withValues(alpha: 0.05),
                  ],
                ),
                border: Border.all(
                    color: const Color(0xFF1A237E).withValues(alpha: 0.15)),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () {
                    final combined = <ScaleEntry>[];
                    combined.addAll(allJaMerged);
                    combined.addAll(allNaoMerged);
                    combined.sort((a, b) => b.date.compareTo(a.date));
                    _abrirPlantoesTotal(
                      context,
                      combined,
                      periodLabel,
                      tipoLabel: 'Total (todos os vínculos)',
                    );
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: Column(
                      children: [
                        Text(
                          'Total (R\$)',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.grey.shade700),
                        ),
                        const SizedBox(height: 6),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            CurrencyFormats.formatBRL(sumTotalPeriod),
                            style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w900,
                                color: Color(0xFF1A237E)),
                          ),
                        ),
                        Text('$countTotalPeriod plantão(ões)',
                            style: TextStyle(
                                fontSize: 10, color: Colors.grey.shade600)),
                        Text('Toque para ver',
                            style: TextStyle(
                                fontSize: 9, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEarningsCard(List<ScaleEntry> entries, DateTime hoje,
      String periodLabel, List<ShiftLocation> locations) {
    final semFinanceiroJa = <ScaleEntry>[];
    final semFinanceiroNao = <ScaleEntry>[];
    final compromissosJa = <ScaleEntry>[];
    final compromissosNao = <ScaleEntry>[];

    for (final e in entries) {
      if (e.isCompromisso) {
        if (e.effectiveJaTiradoParaExibicaoComLocais(hoje, locations)) {
          compromissosJa.add(e);
        } else {
          compromissosNao.add(e);
        }
        continue;
      }
      if (e.temFinanceiroPainelComLocais(locations)) continue;
      if (e.effectiveJaTiradoParaExibicaoComLocais(hoje, locations)) {
        semFinanceiroJa.add(e);
      } else {
        semFinanceiroNao.add(e);
      }
    }

    semFinanceiroJa.sort((a, b) => b.date.compareTo(a.date));
    semFinanceiroNao.sort((a, b) => a.date.compareTo(b.date));
    compromissosJa.sort((a, b) => b.date.compareTo(a.date));
    compromissosNao.sort((a, b) => a.date.compareTo(b.date));

    final todosJa = <ScaleEntry>[...semFinanceiroJa, ...compromissosJa]
      ..sort((a, b) => b.date.compareTo(a.date));
    final todosNao = <ScaleEntry>[...semFinanceiroNao, ...compromissosNao]
      ..sort((a, b) => a.date.compareTo(b.date));
    final todosOrdinarios = <ScaleEntry>[...todosJa, ...todosNao]
      ..sort((a, b) => b.date.compareTo(a.date));

    const String tipoListaOrdinarios = 'Plantões e compromissos (ordinários)';
    final totalLancamentos = todosOrdinarios.length;

    Widget statusRow({
      required String label,
      required int countJa,
      required int countNao,
      required VoidCallback onTapTotal,
      required VoidCallback onTapJa,
      required VoidCallback onTapNao,
      required Color color,
      required IconData icon,
      String naoTiradosLabel = 'Não tirados',
      double titleFont = 12,
      double chipFont = 12,
      double iconSize = 16,
      EdgeInsetsGeometry padding =
          const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    }) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTapTotal,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            width: double.infinity,
            padding: padding,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.20)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: iconSize, color: color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                            fontSize: titleFont,
                            fontWeight: FontWeight.w800,
                            color: color),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded,
                        size: 20, color: Colors.grey.shade500),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: onTapJa,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            'Já tirados: $countJa',
                            style: TextStyle(
                                fontSize: chipFont,
                                fontWeight: FontWeight.w700,
                                color: Colors.green.shade700),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: InkWell(
                        onTap: onTapNao,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            '$naoTiradosLabel: $countNao',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                                fontSize: chipFont,
                                fontWeight: FontWeight.w700,
                                color: Colors.blue.shade700),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(_kDashSurfaceRadius),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 22,
              offset: const Offset(0, 10)),
        ],
        border:
            Border.all(color: const Color(0xFF1A237E).withValues(alpha: 0.14)),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1A237E).withValues(alpha: 0.04),
            Colors.white,
          ],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A237E).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.event_note_rounded,
                    color: Color(0xFF1A237E), size: 26),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Controle de Plantões / Compromissos - ordinários',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1A237E),
                      height: 1.25),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Soma plantões sem financeiro no painel e compromissos. Já tirados: pagos ou dia já passou (plantões sem financeiro). A tirar: hoje ou futuro, ainda não pagos.',
            style: TextStyle(
                fontSize: 13, color: Colors.grey.shade700, height: 1.35),
          ),
          const SizedBox(height: 16),
          if (totalLancamentos == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'Nenhum plantão sem financeiro nem compromisso neste período.',
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontStyle: FontStyle.italic),
              ),
            ),
          statusRow(
            label: 'Plantões / compromissos',
            countJa: todosJa.length,
            countNao: todosNao.length,
            onTapTotal: () => _abrirPlantoesTotal(
              context,
              todosOrdinarios,
              periodLabel,
              tipoLabel: tipoListaOrdinarios,
            ),
            onTapJa: () => _abrirPlantoesJaTirado(context, todosJa, periodLabel,
                tipoLabel: tipoListaOrdinarios),
            onTapNao: () => _abrirPlantoesATirar(context, todosNao, periodLabel,
                tipoLabel: tipoListaOrdinarios),
            color: const Color(0xFF1A237E),
            icon: Icons.event_available_rounded,
            naoTiradosLabel: 'A tirar',
            titleFont: 14,
            chipFont: 14,
            iconSize: 20,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirPlantoesJaTirado(
      BuildContext context, List<ScaleEntry> entries, String periodLabel,
      {String? tipoLabel}) async {
    final title = tipoLabel != null
        ? 'Plantões já tirados — $tipoLabel'
        : 'Plantões já tirados';
    final hideValues = tipoLabel == 'Sem financeiro';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
              // Topo do preview: «Voltar» (esquerda) + X (direita).
              _previewTopBar(ctx),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: AppColors.success.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14)),
                      child: Icon(Icons.check_circle_rounded,
                          color: AppColors.success, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A237E))),
                          Text(periodLabel,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                          Text('${entries.length} plantão(ões)',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.work_off_rounded,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text('Nenhum plantão já tirado no período',
                                style: TextStyle(
                                    fontSize: 16, color: Colors.grey.shade600)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        cacheExtent: 400,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                        itemCount: entries.length,
                        itemBuilder: (context, i) => _activityItem(
                          context,
                          entries[i],
                          isJaTirado: true,
                          hideValue: hideValues,
                        ),
                      ),
              ),
              if (widget.onNavigateTo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        // Evita alternar módulos no mesmo frame do pop (pode gerar tela preta/stack inconsistente).
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          widget.onNavigateTo?.call(3);
                        });
                      },
                      icon: const Icon(Icons.calendar_month_rounded, size: 20),
                      label: const Text('Ver mais no módulo Escalas'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirPlantoesATirar(
      BuildContext context, List<ScaleEntry> entries, String periodLabel,
      {String? tipoLabel}) async {
    final title = tipoLabel != null
        ? 'Plantões não tirados — $tipoLabel'
        : 'Plantões não tirados';
    final hideValues = tipoLabel == 'Sem financeiro';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
              // Topo do preview: «Voltar» (esquerda) + X (direita).
              _previewTopBar(ctx),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(14)),
                      child: Icon(Icons.schedule_rounded,
                          color: Colors.blue.shade700, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A237E))),
                          Text(periodLabel,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                          Text('${entries.length} plantão(ões)',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_available_rounded,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text('Nenhum plantão não tirado no período',
                                style: TextStyle(
                                    fontSize: 16, color: Colors.grey.shade600)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        cacheExtent: 400,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                        itemCount: entries.length,
                        itemBuilder: (context, i) => _activityItem(
                          context,
                          entries[i],
                          isJaTirado: false,
                          hideValue: hideValues,
                        ),
                      ),
              ),
              if (widget.onNavigateTo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        // Evita alternar módulos no mesmo frame do pop (pode gerar tela preta/stack inconsistente).
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          widget.onNavigateTo?.call(3);
                        });
                      },
                      icon: const Icon(Icons.calendar_month_rounded, size: 20),
                      label: const Text('Ver mais no módulo Escalas'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirPlantoesTotal(
      BuildContext context, List<ScaleEntry> entries, String periodLabel,
      {String? tipoLabel}) async {
    final title =
        tipoLabel != null ? 'Plantões — $tipoLabel' : 'Plantões — total';
    final sorted = <ScaleEntry>[...entries]
      ..sort((a, b) => b.date.compareTo(a.date));
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
              // Topo do preview: «Voltar» (esquerda) + X (direita).
              _previewTopBar(ctx),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(14)),
                      child: const Icon(Icons.summarize_rounded,
                          color: AppColors.primary, size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A237E))),
                          Text(periodLabel,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                          Text('${sorted.length} plantão(ões)',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: sorted.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.work_off_rounded,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            const Text('Nenhum plantão no período',
                                style: TextStyle(
                                    fontSize: 16,
                                    color: Colors.grey,
                                    fontStyle: FontStyle.italic)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        cacheExtent: 400,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                        itemCount: sorted.length,
                        itemBuilder: (context, i) => _activityItem(
                            context, sorted[i],
                            isJaTirado: false),
                      ),
              ),
              if (widget.onNavigateTo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          widget.onNavigateTo?.call(3);
                        });
                      },
                      icon: const Icon(Icons.calendar_month_rounded, size: 20),
                      label: const Text('Ver mais no módulo Escalas'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirPlantaoesHoras(BuildContext context,
      List<ScaleEntry> entries, String periodLabel, bool isNoturnas) async {
    final title = isNoturnas ? 'Horas noturnas' : 'Horas diurnas';
    final iconColor = isNoturnas ? Colors.indigo : Colors.orange;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        minChildSize: 0.25,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
              // Topo do preview: «Voltar» (esquerda) + X (direita).
              _previewTopBar(ctx),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: iconColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                          isNoturnas
                              ? Icons.nights_stay_rounded
                              : Icons.wb_sunny_rounded,
                          color: iconColor,
                          size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title,
                              style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A237E))),
                          Text(periodLabel,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                          Text('${entries.length} plantão(ões)',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: entries.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                                isNoturnas
                                    ? Icons.nights_stay_rounded
                                    : Icons.wb_sunny_rounded,
                                size: 64,
                                color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text(
                                'Nenhum plantão com ${isNoturnas ? "horas noturnas" : "horas diurnas"} no período',
                                style: TextStyle(
                                    fontSize: 16, color: Colors.grey.shade600),
                                textAlign: TextAlign.center),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        cacheExtent: 400,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
                        itemCount: entries.length,
                        itemBuilder: (context, i) =>
                            _activityItemHoras(entries[i], isNoturnas),
                      ),
              ),
              if (widget.onNavigateTo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        // Evita alternar módulos no mesmo frame do pop (pode gerar tela preta/stack inconsistente).
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          widget.onNavigateTo?.call(3);
                        });
                      },
                      icon: const Icon(Icons.calendar_month_rounded, size: 20),
                      label: const Text('Ver mais no módulo Escalas'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activityItemHoras(ScaleEntry e, bool isNoturnas) {
    final horas = isNoturnas ? e.hoursNight : e.hoursDay;
    final valor =
        isNoturnas ? (e.hoursNight * e.nightRate) : (e.hoursDay * e.dayRate);
    final color = isNoturnas ? Colors.indigo : Colors.orange;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.15)),
        boxShadow: [
          BoxShadow(
              color: color.withOpacity(0.06),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withOpacity(0.15),
            child: Icon(
                isNoturnas ? Icons.nights_stay_rounded : Icons.wb_sunny_rounded,
                color: color,
                size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label ?? 'Plantão',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                Text(DateFormat('dd MMM', 'pt_BR').format(e.date),
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                    '${horas.toStringAsFixed(1)}h · ${CurrencyFormats.formatBRL(valor)}',
                    style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: color)),
              ],
            ),
          ),
          Text(CurrencyFormats.formatBRL(valor),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  /// [sheetContext] = contexto do item dentro do preview (bottom sheet); fecha o sheet
  /// antes da edição em tela cheia para audiência/compromisso.
  Future<void> _editarItemEscalaNoPainel(
    ScaleEntry e, {
    BuildContext? sheetContext,
  }) async {
    if (!mounted) return;
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    if (scaleEntryRequiresFullEditor(e) && sheetContext != null) {
      final sheetNav = Navigator.of(sheetContext);
      if (sheetNav.canPop()) {
        sheetNav.pop();
        await Future<void>.delayed(Duration.zero);
      }
    }
    if (!mounted) return;
    await ScaleEntryAgendaEdit.editScaleEntry(
      context: context,
      entry: e,
      userDocId: _userFsId,
      profile: widget.profile,
      onPlantaoQuickEdit: () => _showEditarNumeroEscalaObservacoes(e),
      onSaved: () {
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _showEditarNumeroEscalaObservacoes(ScaleEntry e) async {
    if (!mounted) return;
    final edited = await ScalePlantaoEditDialog.show(context, entry: e);
    if (edited == null || e.id == null || !mounted) return;
    try {
      final scaleRef = FirebaseFirestore.instance
          .collection('users')
          .doc(_userFsId)
          .collection('scales')
          .doc(e.id);
      await scaleRef.update(scalePlantaoFirestorePatch(edited));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nº escala e observações atualizados.'),
          ),
        );
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text('Erro ao salvar: ${err.toString().split('\n').first}'),
              backgroundColor: AppColors.error),
        );
      }
    }
  }

  Widget _activityItem(BuildContext context, ScaleEntry e,
      {required bool isJaTirado, bool hideValue = false}) {
    final resumoLinhas = scaleEntryResumoNumberLines(e);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: e.color.withOpacity(0.15),
            child: Icon(Icons.work_outline_rounded, color: e.color, size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.label ?? 'Plantão',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, color: Color(0xFF1A237E))),
                Text(DateFormat('dd MMM', 'pt_BR').format(e.date),
                    style:
                        TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                const SizedBox(height: 4),
                if (resumoLinhas.isEmpty)
                  Text(
                    scaleEntryResumoNumberEmptyLabel(e),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  )
                else
                  ...resumoLinhas.map(
                    (line) => Text(
                      line,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                if ((e.notes ?? '').trim().isNotEmpty)
                  Text(
                    'Observação: ${(e.notes ?? '').trim()}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (!hideValue)
            Text(CurrencyFormats.formatBRL(e.totalValue),
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: Color(0xFF1A237E))),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 22),
            onPressed: () => _editarItemEscalaNoPainel(e, sheetContext: context),
            tooltip: 'Editar',
            style: IconButton.styleFrom(
              foregroundColor: AppColors.primary,
              minimumSize: const Size(40, 40),
            ),
          ),
        ],
      ),
    );
  }

  static String _ocorrenciaDateStr(dynamic v) {
    if (v == null) return '—';
    if (v is Timestamp) return DateFormat('dd/MM/yyyy').format(v.toDate());
    if (v is DateTime) return DateFormat('dd/MM/yyyy').format(v);
    return v.toString();
  }

  /// Barra superior dos sheets/preview de Produtividade (e atalhos do
  /// painel inicial). Pedido do usuário: cada preview tem **«Voltar»** à
  /// esquerda (para o iPhone, sem botão físico, e por paridade total
  /// iOS/Android/Web) + atalho **«Fechar» (X)** à direita.
  Widget _previewTopBar(BuildContext ctx) => buildPreviewTopBar(ctx);

  Future<void> _abrirPontosEmAberto(BuildContext context,
      List<Map<String, dynamic>> ocorrenciasEmAberto) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollController) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
              // Topo do preview: «Voltar» (esquerda) + X (direita) — padrão
              // pedido pelo usuário (iPhone / Android / Web).
              _previewTopBar(ctx),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2962FF).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(Icons.touch_app_rounded,
                          color: Color(0xFF2962FF), size: 28),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Ocorrências em aberto',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1A237E))),
                          Text(
                              '${ocorrenciasEmAberto.length} ocorrência(s) · ainda não usadas para folga',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ocorrenciasEmAberto.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.inbox_rounded,
                                size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 16),
                            Text('Nenhuma ocorrência em aberto',
                                style: TextStyle(
                                    fontSize: 16, color: Colors.grey.shade600)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        controller: scrollController,
                        cacheExtent: 400,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: ocorrenciasEmAberto.length,
                        itemBuilder: (context, i) {
                          final e = ocorrenciasEmAberto[i];
                          final pts = (e['pontuacao'] is int)
                              ? e['pontuacao'] as int
                              : int.tryParse(
                                      (e['pontuacao'] ?? '0').toString()) ??
                                  0;
                          final natureza =
                              (e['naturezaLabel'] ?? '').toString();
                          final numero =
                              (e['numeroOcorrencia'] ?? '').toString();
                          final dataStr = _ocorrenciaDateStr(e['date']);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2962FF).withOpacity(0.05),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                  color: const Color(0xFF2962FF)
                                      .withOpacity(0.15)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF2962FF)
                                        .withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                      child: Text('$pts',
                                          style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                              color: Color(0xFF1A237E)))),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(natureza,
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF1A237E)),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                      if (numero.isNotEmpty)
                                        Text('Nº $numero',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade600)),
                                      const SizedBox(height: 4),
                                      Text(dataStr,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade500)),
                                    ],
                                  ),
                                ),
                                Text('$pts pts',
                                    style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF2962FF))),
                              ],
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

  Future<void> _abrirFolgasNoAno(
      BuildContext context,
      List<String> folgasOrdenadas,
      Map<String, List<Map<String, dynamic>>> folgasAgrupadas) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.3,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollController) {
          final expandedIndices = <int>{};
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2))),
                // Topo do preview «Folgas no ano»: «Voltar» (esquerda) + X
                // (direita). Mesmo padrão dos demais previews.
                _previewTopBar(ctx),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(Icons.beach_access_rounded,
                            color: AppColors.accent, size: 28),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Folgas no ano',
                                style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1A237E))),
                            Text(
                                '${folgasOrdenadas.length} data(s) em que você folgou',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: folgasOrdenadas.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.beach_access_rounded,
                                  size: 64, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              Text('Nenhuma folga registrada no ano',
                                  style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey.shade600)),
                            ],
                          ),
                        )
                      : StatefulBuilder(
                          builder: (context, setModalState) {
                            return ListView.builder(
                              controller: scrollController,
                              cacheExtent: 400,
                              padding:
                                  const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              itemCount: folgasOrdenadas.length,
                              itemBuilder: (context, i) {
                                final key = folgasOrdenadas[i];
                                final parts = key.split('-');
                                final fd = parts.length >= 3
                                    ? DateTime(
                                        int.parse(parts[0]),
                                        int.parse(parts[1]),
                                        int.parse(parts[2]))
                                    : DateTime.now();
                                final dataFolgaStr =
                                    DateFormat('dd/MM/yyyy').format(fd);
                                final diaSemana =
                                    DateFormat('EEEE', 'pt_BR').format(fd);
                                final items = folgasAgrupadas[key] ?? [];
                                int totalPts = 0;
                                for (final o in items) {
                                  totalPts += (o['pontuacao'] is int)
                                      ? o['pontuacao'] as int
                                      : int.tryParse((o['pontuacao'] ?? '0')
                                              .toString()) ??
                                          0;
                                }
                                final isExpanded = expandedIndices.contains(i);
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withOpacity(0.06),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                        color:
                                            AppColors.accent.withOpacity(0.2)),
                                    boxShadow: [
                                      BoxShadow(
                                          color: AppColors.accent
                                              .withOpacity(0.08),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4))
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            18, 16, 18, 10),
                                        child: Row(
                                          children: [
                                            Icon(Icons.calendar_today_rounded,
                                                color: AppColors.accent,
                                                size: 22),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Text(dataFolgaStr,
                                                      style: const TextStyle(
                                                          fontSize: 16,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: Color(
                                                              0xFF1A237E))),
                                                  Text(diaSemana,
                                                      style: TextStyle(
                                                          fontSize: 12,
                                                          color: Colors
                                                              .grey.shade600)),
                                                ],
                                              ),
                                            ),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 10,
                                                      vertical: 6),
                                              decoration: BoxDecoration(
                                                color: AppColors.accent
                                                    .withOpacity(0.2),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: Text('$totalPts pts',
                                                  style: const TextStyle(
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w800,
                                                      color:
                                                          Color(0xFF0D9488))),
                                            ),
                                            const SizedBox(width: 8),
                                            Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                onTap: () => setModalState(() {
                                                  if (expandedIndices
                                                      .contains(i)) {
                                                    expandedIndices.remove(i);
                                                  } else {
                                                    expandedIndices.add(i);
                                                  }
                                                }),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12,
                                                      vertical: 8),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                          isExpanded
                                                              ? Icons
                                                                  .expand_less_rounded
                                                              : Icons
                                                                  .expand_more_rounded,
                                                          color:
                                                              AppColors.accent,
                                                          size: 22),
                                                      const SizedBox(width: 4),
                                                      Text(
                                                          isExpanded
                                                              ? 'Ocultar'
                                                              : 'Ver ocorrências',
                                                          style: const TextStyle(
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700,
                                                              color: Color(
                                                                  0xFF0D9488))),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (isExpanded) ...[
                                        const Divider(
                                            height: 1,
                                            indent: 18,
                                            endIndent: 18),
                                        Padding(
                                          padding: const EdgeInsets.fromLTRB(
                                              18, 8, 18, 4),
                                          child: Text(
                                              'Ocorrências (RAI) usadas para esta folga:',
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.w700,
                                                  color: Colors.grey.shade700)),
                                        ),
                                        ...items.map((e) {
                                          final pts = (e['pontuacao'] is int)
                                              ? e['pontuacao'] as int
                                              : int.tryParse(
                                                      (e['pontuacao'] ?? '0')
                                                          .toString()) ??
                                                  0;
                                          final natureza =
                                              (e['naturezaLabel'] ?? '')
                                                  .toString();
                                          final numero =
                                              (e['numeroOcorrencia'] ?? '')
                                                  .toString();
                                          final dataStr =
                                              _ocorrenciaDateStr(e['date']);
                                          return Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                18, 6, 18, 10),
                                            child: Row(
                                              children: [
                                                SizedBox(
                                                  width: 36,
                                                  child: Text('$pts pts',
                                                      style: const TextStyle(
                                                          fontSize: 13,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                          color: Color(
                                                              0xFF1A237E))),
                                                ),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      Text(natureza,
                                                          style: TextStyle(
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                              color: Colors.grey
                                                                  .shade800),
                                                          maxLines: 2,
                                                          overflow: TextOverflow
                                                              .ellipsis),
                                                      if (numero.isNotEmpty)
                                                        Text(
                                                            'Nº $numero · $dataStr',
                                                            style: TextStyle(
                                                                fontSize: 11,
                                                                color: Colors
                                                                    .grey
                                                                    .shade500)),
                                                    ],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                        }),
                                        const SizedBox(height: 12),
                                      ],
                                    ],
                                  ),
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Chips de período no painel: em telas estreitas usa **scroll horizontal**
  /// para todos os filtros ficarem acessíveis (web, iOS, Android). Em
  /// telas largas mantém [Wrap] (layout denso).
  Widget _dashChipRowScrollOrWrap({
    required double maxWidth,
    required List<Widget> chips,
    double wideThreshold = 520,
    double spacing = 10,
    double runSpacing = 8,
  }) {
    if (maxWidth >= wideThreshold) {
      return Wrap(
        spacing: spacing,
        runSpacing: runSpacing,
        children: chips,
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) SizedBox(width: spacing),
            chips[i],
          ],
          SizedBox(width: spacing),
        ],
      ),
    );
  }

  Widget _buildProdutividadeSection() {
    final ranges = _produtividadeRanges();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: OcorrenciasService().watch(_userFsId),
      builder: (context, snap) {
        final docs = snap.data?.docs ?? [];
        final ocorrencias = docs.map((d) {
          final m = Map<String, dynamic>.from(d.data());
          m['id'] = d.id;
          return m;
        }).toList();

        return FutureBuilder<int>(
          future: ProdutividadeConfigService().getPontuacaoParaFolga(_userFsId),
          builder: (context, folgaSnap) {
            final pontuacaoParaFolga = folgaSnap.data ??
                ProdutividadeConfigService.defaultPontuacaoParaFolga;

            // Intervalo global do filtro selecionado (Semanal / Quinzenal /
            // Mensal / Anual / Por período). Os cards «Pontos em aberto» e
            // «Folgas no período» devem respeitar exatamente esse intervalo
            // — antes ignoravam e mostravam dados de qualquer época, o que
            // confundia o usuário (ex.: «4 em aberto» em maio quando todos
            // os pontos foram lançados em abril).
            final DateTime sectionStart = ranges.isNotEmpty
                ? ranges.first.$1
                : DateTime(DateTime.now().year, 1, 1);
            final DateTime sectionEnd = ranges.isNotEmpty
                ? ranges.last.$2
                : DateTime(DateTime.now().year, 12, 31, 23, 59, 59);

            DateTime? _asDate(dynamic v) {
              if (v is Timestamp) return v.toDate();
              if (v is DateTime) return v;
              return null;
            }

            bool _dentroDoPeriodo(DateTime d) =>
                !d.isBefore(sectionStart) && !d.isAfter(sectionEnd);

            int totalEmAberto = 0;
            final folgaDatesAno = <String>{};
            final folgasAgrupadas = <String, List<Map<String, dynamic>>>{};
            for (final e in ocorrencias) {
              final pts = (e['pontuacao'] is int)
                  ? e['pontuacao'] as int
                  : int.tryParse((e['pontuacao'] ?? '0').toString()) ?? 0;
              final folgaDate = _asDate(e['folgaDate']);
              final ocDate = _asDate(e['date']);
              if (folgaDate == null) {
                // «Em aberto» só conta quando a data da ocorrência está
                // dentro do filtro selecionado (Mensal, Anual, Por período…).
                if (ocDate != null && _dentroDoPeriodo(ocDate)) {
                  totalEmAberto += pts;
                }
              } else {
                if (_dentroDoPeriodo(folgaDate)) {
                  final key =
                      '${folgaDate.year}-${folgaDate.month.toString().padLeft(2, '0')}-${folgaDate.day.toString().padLeft(2, '0')}';
                  folgaDatesAno.add(key);
                  folgasAgrupadas.putIfAbsent(key, () => []).add(e);
                }
              }
            }
            final ocorrenciasEmAberto = ocorrencias.where((o) {
              if (o['folgaDate'] != null) return false;
              final d = _asDate(o['date']);
              return d != null && _dentroDoPeriodo(d);
            }).toList();
            ocorrenciasEmAberto.sort((a, b) {
              final da = a['date'];
              final db = b['date'];
              DateTime? ta =
                  da is Timestamp ? da.toDate() : (da is DateTime ? da : null);
              DateTime? tb =
                  db is Timestamp ? db.toDate() : (db is DateTime ? db : null);
              if (ta == null || tb == null) return 0;
              return tb.compareTo(ta);
            });
            final folgasOrdenadas = folgaDatesAno.toList()
              ..sort((a, b) => b.compareTo(a));

            final byRange = <int, (int, int)>{};
            for (final e in ranges.asMap().entries) {
              final idx = e.key;
              final (rangeStart, rangeEnd) = e.value;
              int emAberto = 0, usadoFolga = 0;
              for (final o in ocorrencias) {
                final pts = (o['pontuacao'] is int)
                    ? o['pontuacao'] as int
                    : int.tryParse((o['pontuacao'] ?? '0').toString()) ?? 0;
                final date = o['date'];
                DateTime? dt;
                if (date is Timestamp) dt = date.toDate();
                if (date is DateTime) dt = date;
                final folgaDate = o['folgaDate'];
                DateTime? fdt;
                if (folgaDate is Timestamp) fdt = folgaDate.toDate();
                if (folgaDate is DateTime) fdt = folgaDate;
                if (fdt != null) {
                  if (!fdt.isBefore(rangeStart) && !fdt.isAfter(rangeEnd))
                    usadoFolga += pts;
                } else if (dt != null) {
                  if (!dt.isBefore(rangeStart) && !dt.isAfter(rangeEnd))
                    emAberto += pts;
                }
              }
              byRange[idx] = (emAberto, usadoFolga);
            }

            double maxVal = 1.0;
            for (final v in byRange.values) {
              if (v.$1 > maxVal) maxVal = v.$1.toDouble();
              if (v.$2 > maxVal) maxVal = v.$2.toDouble();
            }
            const maxY = 100.0;
            final barGroups = byRange.entries.map((e) {
              final (emAberto, usadoFolga) = e.value;
              final scale = maxVal > 0 ? maxY / maxVal : 1.0;
              return BarChartGroupData(
                x: e.key,
                barRods: [
                  BarChartRodData(
                    toY: (emAberto * scale).clamp(0.0, maxY),
                    color: const Color(0xFF2962FF),
                    width: 12,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                  BarChartRodData(
                    toY: (usadoFolga * scale).clamp(0.0, maxY),
                    color: AppColors.success,
                    width: 12,
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
                showingTooltipIndicators: [],
              );
            }).toList();

            return Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 20,
                      offset: const Offset(0, 8)),
                  BoxShadow(
                      color: AppColors.accent.withOpacity(0.06),
                      blurRadius: 24,
                      offset: const Offset(0, 4)),
                ],
                border: Border.all(
                    color: Colors.grey.shade100.withOpacity(0.8), width: 1),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => widget.onNavigateTo?.call(5),
                    child: Row(
                      children: [
                        Icon(Icons.assignment_rounded,
                            size: 22, color: AppColors.accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildSectionTitle(
                              'Controle de Produtividade / Ocorrências'),
                        ),
                        if (widget.onNavigateTo != null) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.arrow_forward_ios_rounded,
                              size: 14, color: Colors.grey.shade600),
                        ],
                      ],
                    ),
                  ),
                  if (widget.onNavigateTo != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4, left: 32),
                      child: Text('Toque para abrir o módulo',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade600)),
                    ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (ctx, c) => _dashChipRowScrollOrWrap(
                      maxWidth: c.maxWidth,
                      wideThreshold: 520,
                      spacing: 10,
                      runSpacing: 8,
                      chips: _produtividadePeriods
                          .map((p) => ChoiceChip(
                                label: Text(p,
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: _produtividadeChartPeriod == p
                                            ? Colors.white
                                            : const Color(0xFF1A237E))),
                                selected: _produtividadeChartPeriod == p,
                                onSelected: (_) {
                                  setState(() {
                                    _produtividadeChartPeriod = p;
                                    if (p == 'Por período') {
                                      final now = DateTime.now();
                                      _produtividadeCustomStart ??=
                                          DateTime(now.year, now.month, 1);
                                      _produtividadeCustomEnd ??= now;
                                    }
                                  });
                                },
                                selectedColor: AppColors.accent,
                                backgroundColor: Colors.grey.shade50,
                                side: BorderSide(
                                    color: _produtividadeChartPeriod == p
                                        ? AppColors.accent
                                        : Colors.grey.shade300),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 8),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16)),
                              ))
                          .toList(),
                    ),
                  ),
                  if (_produtividadeChartPeriod == 'Por período') ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _produtividadeCustomStart ??
                                      DateTime(now.year, now.month, 1),
                                  firstDate: DateTime(2000),
                                  lastDate: DateTime(2030));
                              if (picked != null && mounted)
                                setState(
                                    () => _produtividadeCustomStart = picked);
                            },
                            icon: const Icon(Icons.calendar_today_rounded,
                                size: 18),
                            label: Text(
                                'Início: ${DateFormat('dd/MM/yyyy', 'pt_BR').format(_produtividadeCustomStart ?? DateTime.now())}',
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final now = DateTime.now();
                              final picked = await showDatePicker(
                                  context: context,
                                  initialDate: _produtividadeCustomEnd ?? now,
                                  firstDate: _produtividadeCustomStart ??
                                      DateTime(2000),
                                  lastDate: DateTime(2030));
                              if (picked != null && mounted)
                                setState(
                                    () => _produtividadeCustomEnd = picked);
                            },
                            icon: const Icon(Icons.event_rounded, size: 18),
                            label: Text(
                                'Fim: ${DateFormat('dd/MM/yyyy', 'pt_BR').format(_produtividadeCustomEnd ?? DateTime.now())}',
                                style: const TextStyle(fontSize: 12)),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (totalEmAberto >= pontuacaoParaFolga)
                    Container(
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            AppColors.success.withOpacity(0.15),
                            AppColors.success.withOpacity(0.08)
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.success.withOpacity(0.4)),
                        boxShadow: [
                          BoxShadow(
                              color: AppColors.success.withOpacity(0.12),
                              blurRadius: 12,
                              offset: const Offset(0, 4))
                        ],
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.celebration_rounded,
                              color: AppColors.success, size: 32),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Parabéns profissional, você já pode marcar sua folga!',
                              style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.success),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _abrirPontosEmAberto(
                                context, ocorrenciasEmAberto),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color:
                                    const Color(0xFF2962FF).withOpacity(0.06),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                      color: const Color(0xFF2962FF)
                                          .withOpacity(0.1),
                                      blurRadius: 14,
                                      offset: const Offset(0, 6))
                                ],
                                border: Border.all(
                                    color: const Color(0xFF2962FF)
                                        .withOpacity(0.2)),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.touch_app_rounded,
                                      color: const Color(0xFF2962FF), size: 30),
                                  const SizedBox(height: 10),
                                  Text('Pontos em aberto',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade700)),
                                  const SizedBox(height: 6),
                                  Text('$totalEmAberto',
                                      style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF1A237E))),
                                  const SizedBox(height: 2),
                                  Text('Toque para ver lista',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _abrirFolgasNoAno(
                                context, folgasOrdenadas, folgasAgrupadas),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(20),
                                boxShadow: [
                                  BoxShadow(
                                      color: AppColors.accent.withOpacity(0.12),
                                      blurRadius: 14,
                                      offset: const Offset(0, 6))
                                ],
                                border: Border.all(
                                    color: AppColors.accent.withOpacity(0.25)),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.beach_access_rounded,
                                      color: AppColors.accent, size: 30),
                                  const SizedBox(height: 10),
                                  Text(_folgasCardLabel(),
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade700)),
                                  const SizedBox(height: 6),
                                  Text('${folgaDatesAno.length}',
                                      style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                          color: Color(0xFF1A237E))),
                                  const SizedBox(height: 2),
                                  Text('Toque para ver datas',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey.shade500)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 220,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.04),
                            blurRadius: 16,
                            offset: const Offset(0, 4))
                      ],
                    ),
                    child: barGroups.isEmpty
                        ? Center(
                            child: Text('Nenhuma ocorrência no período.',
                                style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w600)))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                          color: const Color(0xFF2962FF),
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          boxShadow: [
                                            BoxShadow(
                                                color: const Color(0xFF2962FF)
                                                    .withOpacity(0.3),
                                                blurRadius: 4)
                                          ])),
                                  const SizedBox(width: 8),
                                  const Text('Em aberto',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF374151))),
                                  const SizedBox(width: 20),
                                  Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                          color: AppColors.success,
                                          borderRadius:
                                              BorderRadius.circular(4),
                                          boxShadow: [
                                            BoxShadow(
                                                color: AppColors.success
                                                    .withOpacity(0.3),
                                                blurRadius: 4)
                                          ])),
                                  const SizedBox(width: 8),
                                  const Text('Já usado para folga',
                                      style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xFF374151))),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Expanded(
                                child: BarChart(
                                  BarChartData(
                                    alignment: BarChartAlignment.spaceAround,
                                    maxY: maxY,
                                    barGroups: barGroups,
                                    titlesData: FlTitlesData(
                                      show: true,
                                      bottomTitles: AxisTitles(
                                        sideTitles: SideTitles(
                                          showTitles: true,
                                          getTitlesWidget: (v, meta) {
                                            final idx = v.toInt();
                                            if (idx >= 0 &&
                                                idx < ranges.length) {
                                              final (s, _) = ranges[idx];
                                              if (_produtividadeChartPeriod ==
                                                      'Mensal' ||
                                                  _produtividadeChartPeriod ==
                                                      'Anual')
                                                return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 6),
                                                    child: Text(
                                                        DateFormat(
                                                                'MMM', 'pt_BR')
                                                            .format(s),
                                                        style: const TextStyle(
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600)));
                                              if (_produtividadeChartPeriod ==
                                                  'Quinzenal')
                                                return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 6),
                                                    child: Text(
                                                        '${s.day}/${s.month}',
                                                        style: const TextStyle(
                                                            fontSize: 9,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600)));
                                              if (_produtividadeChartPeriod ==
                                                  'Por período')
                                                return Padding(
                                                    padding:
                                                        const EdgeInsets.only(
                                                            top: 6),
                                                    child: Text('Período',
                                                        style: const TextStyle(
                                                            fontSize: 9,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w600)));
                                              return Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          top: 6),
                                                  child: Text(
                                                      '${s.day}/${s.month}',
                                                      style: const TextStyle(
                                                          fontSize: 9,
                                                          fontWeight: FontWeight
                                                              .w600)));
                                            }
                                            return const SizedBox.shrink();
                                          },
                                          reservedSize: 22,
                                          interval: 1,
                                        ),
                                      ),
                                      leftTitles: const AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false)),
                                      topTitles: const AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false)),
                                      rightTitles: const AxisTitles(
                                          sideTitles:
                                              SideTitles(showTitles: false)),
                                    ),
                                    gridData: FlGridData(show: false),
                                    borderData: FlBorderData(show: false),
                                    barTouchData: BarTouchData(enabled: false),
                                  ),
                                  swapAnimationDuration:
                                      const Duration(milliseconds: 300),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

/// Sheet de receitas ou despesas pendentes no painel: modo seleção e exclusão em lote.
class _DashboardPendingListSheetContent extends StatefulWidget {
  final String title;
  final String? subtitle;
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

  const _DashboardPendingListSheetContent({
    required this.title,
    this.subtitle,
    required this.iconColor,
    required this.list,
    required this.scrollController,
    required this.emptyMessage,
    required this.buildItem,
    required this.onDeleteBatch,
  });

  @override
  State<_DashboardPendingListSheetContent> createState() =>
      _DashboardPendingListSheetContentState();
}

class _DashboardPendingListSheetContentState
    extends State<_DashboardPendingListSheetContent> {
  bool _selectionMode = false;
  final Set<String> _selectedIds = {};
  bool _deletingBatch = false;
  FinanceFaturaTxSortMode _sortMode = FinanceFaturaTxSortMode.dateDesc;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (await shouldShowSheetSelectionHint() && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppStrings.sheetSelectionHint),
          behavior: SnackBarBehavior.floating,
        ));
        markSheetSelectionHintShown();
      }
    });
  }

  double get _totalValue => widget.list.fold<double>(
      0, (s, e) => s + ((e['amount'] ?? 0) as num).toDouble().abs());

  Widget _buildHeaderActions() {
    if (!_selectionMode) {
      return Semantics(
        label: AppStrings.semanticsSelect,
        button: true,
        child: TextButton.icon(
          onPressed: () => setState(() => _selectionMode = true),
          icon: const Icon(Icons.checklist_rounded, size: 20),
          label: Text(AppStrings.select),
          style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.padded),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        TextButton(
          onPressed: () => setState(() {
            _selectionMode = false;
            _selectedIds.clear();
          }),
          style: TextButton.styleFrom(
              minimumSize: const Size(48, 48),
              tapTargetSize: MaterialTapTargetSize.padded),
          child: const Text('Cancelar'),
        ),
        if (_selectedIds.isNotEmpty)
          FilledButton.icon(
            onPressed: _deletingBatch
                ? null
                : () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text(AppStrings.deleteSelected),
                        content: Text(
                            '${_selectedIds.length} ${AppStrings.deleteSelectedConfirm}'),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: Text(AppStrings.cancel)),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.error),
                              child: Text(AppStrings.delete)),
                        ],
                      ),
                    );
                    if (confirm == true && mounted) {
                      setState(() => _deletingBatch = true);
                      await widget.onDeleteBatch(_selectedIds.toList());
                      if (mounted) setState(() => _deletingBatch = false);
                    }
                  },
            icon: _deletingBatch
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.delete_outline_rounded, size: 20),
            label: Text(_deletingBatch
                ? 'Excluindo...'
                : 'Excluir (${_selectedIds.length})'),
            style: FilledButton.styleFrom(
                backgroundColor: AppColors.error,
                minimumSize: const Size(48, 48),
                tapTargetSize: MaterialTapTargetSize.padded),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    final width = MediaQuery.sizeOf(context).width;
    final useTwoRowHeader = width < 500 || _selectionMode;
    final sortedList = FinanceFaturaTransactionSort.sortedMaps(widget.list, _sortMode);
    return Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            // Topo do preview: «Voltar» (esquerda) + X (direita).
            buildPreviewTopBar(context),
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
                              decoration: BoxDecoration(
                                  color: widget.iconColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(14)),
                              child: Icon(Icons.schedule_rounded,
                                  color: widget.iconColor, size: 28),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(widget.title,
                                      style: const TextStyle(
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF1A237E)),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis),
                                  if (widget.subtitle != null)
                                    Text(widget.subtitle!,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey.shade600),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                  if (widget.list.isNotEmpty)
                                    Text(
                                        'Total: ${CurrencyFormats.formatBRL(_totalValue)}',
                                        style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w700,
                                            color: widget.iconColor)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        _buildHeaderActions(),
                      ],
                    )
                  : Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                              color: widget.iconColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(14)),
                          child: Icon(Icons.schedule_rounded,
                              color: widget.iconColor, size: 28),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(widget.title,
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1A237E)),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis),
                              if (widget.subtitle != null)
                                Text(widget.subtitle!,
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                              if (widget.list.isNotEmpty)
                                Text(
                                    'Total: ${CurrencyFormats.formatBRL(_totalValue)}',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: widget.iconColor)),
                            ],
                          ),
                        ),
                        _buildHeaderActions(),
                      ],
                    ),
            ),
            if (widget.list.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: FinanceTransactionSortBar(
                  value: _sortMode,
                  onChanged: (mode) => setState(() => _sortMode = mode),
                ),
              ),
            Expanded(
              child: widget.list.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_rounded,
                              size: 48, color: Colors.grey.shade400),
                          const SizedBox(height: 12),
                          Text(widget.emptyMessage,
                              style: TextStyle(
                                  fontSize: 14, color: Colors.grey.shade600)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: widget.scrollController,
                      cacheExtent: 400,
                      padding: EdgeInsets.fromLTRB(
                          20, 0, 20, 24 + bottomPadding + 16),
                      itemCount: sortedList.length,
                      itemBuilder: (_, i) {
                        final e = sortedList[i];
                        final id = (e['id'] ?? '').toString();
                        return widget.buildItem(
                          context,
                          e,
                          selectionMode: _selectionMode,
                          isSelected: _selectedIds.contains(id),
                          onToggleSelect: () => setState(() {
                            if (_selectedIds.contains(id))
                              _selectedIds.remove(id);
                            else
                              _selectedIds.add(id);
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
}

/// Barra superior padrão dos previews/sheets do painel inicial.
///
/// Pedido do usuário: cada preview tem **«Voltar»** à esquerda (paridade
/// total iPhone / iOS / Android / Web, sem depender de botão físico) +
/// atalho **«Fechar» (X)** à direita. Reutilizado em todos os sheets do
/// Painel Inicial e nos widgets internos como `_DashboardPendingListSheetContent`.
Widget buildPreviewTopBar(BuildContext ctx) => previewSheetTopBar(ctx);
