import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import '../constants/finance_account_visuals.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../services/finance_accounts_service.dart';
import '../services/finance_opening_balance_service.dart';
import '../services/sensitive_balance_preferences.dart';
import '../screens/finance_screen.dart' show FinanceInsightScope;
import '../utils/finance_account_category_sheet_launcher.dart';
import '../utils/finance_account_balance_utils.dart';
import '../utils/finance_fora_dos_totais.dart';
import '../utils/finance_line_opening.dart';
import '../utils/finance_transactions_realtime.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/home_painel_resumo.dart';
import '../utils/premium_upgrade.dart';
import '../widgets/finance_sparkline.dart';
import 'categorias_rosca_moderna.dart';

/// Construtor do bloco que entra logo abaixo do carrossel de contas (os cards
/// de pendentes do Início). Recebe as contas e o «ocultar valores» do painel.
typedef HomeFinancePendentesBuilder = Widget Function(
  BuildContext context,
  List<FinanceAccount> contas,
  bool ocultarValores,
);

/// Últimos lançamentos por período e últimas contas — o Início desmonta ao
/// trocar de módulo; ao voltar pinta na hora com o último valor bom.
final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
    _ultimosDocs = {};
final Map<String, List<FinanceAccount>> _ultimasContas = {};

/// Resumo financeiro no Início (padrão Controle Total): período, saldo
/// acumulado, receitas × despesas, carrossel de contas, pendentes,
/// «Evolução do Saldo» (só o pago) e despesas por categoria (pizza 3D).
///
/// Nada de leitura nova: os lançamentos do período vêm de UMA escuta
/// ([financeTransactionsPeriodDocs]) guardada no estado, a abertura vem do
/// [FinanceOpeningBalanceService] (cache) e os gráficos usam os mesmos docs.
class HomeFinanceOverviewPanel extends StatefulWidget {
  const HomeFinanceOverviewPanel({
    super.key,
    required this.uid,
    required this.profile,
    required this.onOpenFinanceiro,
    this.pendentesBuilder,
  });

  final String uid;
  final UserProfile profile;
  final VoidCallback onOpenFinanceiro;
  final HomeFinancePendentesBuilder? pendentesBuilder;

  @override
  State<HomeFinanceOverviewPanel> createState() =>
      _HomeFinanceOverviewPanelState();
}

class _HomeFinanceOverviewPanelState extends State<HomeFinanceOverviewPanel> {
  static const _periods = ['Mês anterior', 'Mensal', 'Anual', 'Por período'];

  static const _kVerde = Color(0xFF16A34A);
  static const _kVermelho = Color(0xFFDC2626);

  bool _hideBalances = false;
  String _selectedPeriod = 'Mensal';
  DateTime? _customRangeStart;
  DateTime? _customRangeEnd;

  String _saldoAberturaKey = '';
  ({double total, Map<String, double> byAccount})? _saldoAberturaCached;

  // Escutas guardadas (nunca criadas no build).
  String _docsKey = '';
  Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>>? _docsStream;
  late Stream<List<FinanceAccount>> _contasStream;

  /// Prazo da 1ª carga: passou e nada chegou → mostra «Tentar de novo» em vez
  /// de deixar os cards girando para sempre.
  static const _kPrazoCarga = Duration(seconds: 20);
  Timer? _prazoTimer;
  bool _demorou = false;
  int _tentativa = 0;
  Timer? _prazoContasTimer;
  bool _contasDemorou = false;

  void _armarPrazoContas() {
    _prazoContasTimer?.cancel();
    _contasDemorou = false;
    if (_ultimasContas[_userFsId] != null) return;
    _prazoContasTimer = Timer(_kPrazoCarga, () {
      if (!mounted || _ultimasContas[_userFsId] != null) return;
      setState(() => _contasDemorou = true);
    });
  }

  String get _userFsId => firestoreUserDocIdForAppShell(widget.uid);

  (DateTime, DateTime) _rangeForPeriod() {
    final now = DateTime.now();
    switch (_selectedPeriod) {
      case 'Mês anterior':
        final lastMonth = DateTime(now.year, now.month - 1);
        return (
          DateTime(lastMonth.year, lastMonth.month, 1),
          DateTime(lastMonth.year, lastMonth.month + 1, 0, 23, 59, 59),
        );
      case 'Mensal':
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 0, 23, 59, 59),
        );
      case 'Anual':
        return (
          DateTime(now.year, 1, 1),
          DateTime(now.year, 12, 31, 23, 59, 59),
        );
      case 'Por período':
        final start = _customRangeStart ?? DateTime(now.year, now.month, 1);
        final end = _customRangeEnd ?? now;
        final endNorm = end.isBefore(start) ? start : end;
        return (
          DateTime(start.year, start.month, start.day),
          DateTime(endNorm.year, endNorm.month, endNorm.day, 23, 59, 59),
        );
      default:
        return (
          DateTime(now.year, now.month, 1),
          DateTime(now.year, now.month + 1, 0, 23, 59, 59),
        );
    }
  }

  String _periodLabel(DateTime start, DateTime end) {
    switch (_selectedPeriod) {
      case 'Mês anterior':
      case 'Mensal':
        return '${_monthName(start.month)} ${start.year}';
      case 'Anual':
        return 'Ano ${start.year}';
      case 'Por período':
        final df = DateFormat('dd/MM/yy', 'pt_BR');
        return '${df.format(start)} — ${df.format(end)}';
      default:
        return '${_monthName(start.month)} ${start.year}';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _contasStream = FinanceAccountsService().streamAccounts(_userFsId).map((l) {
      _ultimasContas[_userFsId] = l;
      return l;
    });
    _armarPrazoContas();
    final (start, end) = _rangeForPeriod();
    _garantirStreamDocs(start, end);
    _ensureSaldoAberturaForPeriod(start);
    FinanceOpeningBalanceService.revision.addListener(_onOpeningRevision);
  }

  Timer? _openingReloadTimer;

  @override
  void dispose() {
    FinanceOpeningBalanceService.revision.removeListener(_onOpeningRevision);
    _openingReloadTimer?.cancel();
    _prazoTimer?.cancel();
    _prazoContasTimer?.cancel();
    super.dispose();
  }

  String _chaveDocs(DateTime start, DateTime end) =>
      '$_userFsId|${start.millisecondsSinceEpoch}|${end.millisecondsSinceEpoch}';

  /// Uma escuta por período — trocar de período troca a escuta; rebuild não.
  void _garantirStreamDocs(DateTime start, DateTime end) {
    final key = _chaveDocs(start, end);
    if (key == _docsKey && _docsStream != null) return;
    _docsKey = key;
    _demorou = false;
    _prazoTimer?.cancel();
    if (_ultimosDocs[key] == null) {
      _prazoTimer = Timer(_kPrazoCarga, () {
        if (!mounted || _docsKey != key || _ultimosDocs[key] != null) return;
        setState(() => _demorou = true);
      });
    }
    _docsStream = financeTransactionsPeriodDocs(
      uid: _userFsId,
      rangeStart: start,
      rangeEnd: end,
    ).map((docs) {
      _ultimosDocs[key] = docs;
      _prazoTimer?.cancel();
      return docs;
    });
  }

  /// «Tentar de novo»: refaz as escutas (lançamentos e contas) e a abertura.
  void _tentarDeNovo() {
    final (start, end) = _rangeForPeriod();
    setState(() {
      _tentativa++;
      _docsKey = '';
      _docsStream = null;
      _contasStream =
          FinanceAccountsService().streamAccounts(_userFsId).map((l) {
        _ultimasContas[_userFsId] = l;
        return l;
      });
      _armarPrazoContas();
      _garantirStreamDocs(start, end);
    });
    _saldoAberturaKey = '';
    _ensureSaldoAberturaForPeriod(start);
  }

  Widget _cardErroCarga(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: context.appPanelDecoration(radius: 16),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFEA580C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Não foi possível carregar o resumo financeiro agora. '
              'Verifique a conexão.',
              style: TextStyle(
                  fontSize: 13, height: 1.35, color: context.appTextPrimary),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _tentarDeNovo,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('Tentar de novo'),
          ),
        ],
      ),
    );
  }

  /// Saldo de abertura mudou em cache (pagamento confirmado/lançamento antes do
  /// período, ou recálculo depois do servidor): troca o número dos cards na
  /// hora. Antes o painel só relia a abertura ao trocar de período.
  void _onOpeningRevision() {
    if (!mounted) return;
    final (start, _) = _rangeForPeriod();
    final key = '${start.year}-${start.month}-${start.day}';
    if (_saldoAberturaKey != key) return;
    final peek = FinanceOpeningBalanceService.peekCached(
      uid: widget.uid,
      periodStart: start,
      loadAccounts: true,
    );
    if (peek != null) {
      setState(() => _saldoAberturaCached = peek);
      return;
    }
    // Sem valor em cache: o Financeiro costuma recarregar junto — espera um
    // pouco e reaproveita; senão recarrega aqui, mantendo o número exibido.
    _openingReloadTimer?.cancel();
    _openingReloadTimer = Timer(const Duration(milliseconds: 600), () {
      if (!mounted || _saldoAberturaKey != key) return;
      final again = FinanceOpeningBalanceService.peekCached(
        uid: widget.uid,
        periodStart: start,
        loadAccounts: true,
      );
      if (again != null) {
        setState(() => _saldoAberturaCached = again);
        return;
      }
      unawaited(_loadSaldoAberturaIntoState(start, keepDisplayed: true));
    });
  }

  Future<void> _loadPrefs() async {
    final h = await SensitiveBalancePreferences.load();
    if (mounted) setState(() => _hideBalances = h);
  }

  void _ensureSaldoAberturaForPeriod(DateTime periodStart) {
    final key = '${periodStart.year}-${periodStart.month}-${periodStart.day}';
    if (_saldoAberturaKey == key && _saldoAberturaCached != null) return;
    _saldoAberturaKey = key;
    // Primeiro o cache com contas (cards do banco certos de saída); senão o
    // só-total; a leitura completa vem em seguida sem apagar o que já está.
    final peek = FinanceOpeningBalanceService.peekCached(
          uid: widget.uid,
          periodStart: periodStart,
          loadAccounts: true,
        ) ??
        FinanceOpeningBalanceService.peekCached(
          uid: widget.uid,
          periodStart: periodStart,
          loadAccounts: false,
        );
    if (peek != null) {
      _saldoAberturaCached = peek;
    }
    unawaited(
        _loadSaldoAberturaIntoState(periodStart, keepDisplayed: peek != null));
  }

  /// [keepDisplayed]: recarga depois de mutação — sem a fase «só total» (vem
  /// sem saldo por conta e fazia os cards do banco pularem).
  Future<void> _loadSaldoAberturaIntoState(
    DateTime periodStart, {
    bool keepDisplayed = false,
  }) async {
    // Falha/demora na abertura não pode derrubar o painel: mantém o valor
    // exibido (ou 0) e os lançamentos do período continuam aparecendo.
    try {
      await _loadSaldoAberturaCore(periodStart, keepDisplayed: keepDisplayed);
    } catch (e) {
      debugPrint('HomeFinanceOverviewPanel: abertura falhou: $e');
    }
  }

  Future<void> _loadSaldoAberturaCore(
    DateTime periodStart, {
    required bool keepDisplayed,
  }) async {
    if (!keepDisplayed || _saldoAberturaCached == null) {
      final fast = await FinanceOpeningBalanceService.load(
        uid: widget.uid,
        periodStart: periodStart,
        loadAccounts: false,
      ).timeout(const Duration(seconds: 25));
      if (!mounted ||
          _saldoAberturaKey !=
              '${periodStart.year}-${periodStart.month}-${periodStart.day}') {
        return;
      }
      setState(() => _saldoAberturaCached = fast);
    }
    final full = await FinanceOpeningBalanceService.load(
      uid: widget.uid,
      periodStart: periodStart,
      loadAccounts: true,
    ).timeout(const Duration(seconds: 40));
    if (!mounted ||
        _saldoAberturaKey !=
            '${periodStart.year}-${periodStart.month}-${periodStart.day}') {
      return;
    }
    setState(() => _saldoAberturaCached = full);
  }

  void _applyPeriod(String period) {
    setState(() {
      _selectedPeriod = period;
      if (period == 'Por período' && _customRangeStart == null) {
        final now = DateTime.now();
        _customRangeStart = DateTime(now.year, now.month, 1);
        _customRangeEnd = now;
      }
      final (start, end) = _rangeForPeriod();
      _garantirStreamDocs(start, end);
    });
    final (start, _) = _rangeForPeriod();
    _ensureSaldoAberturaForPeriod(start);
  }

  void _periodoPersonalizadoMudou() {
    final (start, end) = _rangeForPeriod();
    setState(() => _garantirStreamDocs(start, end));
    _ensureSaldoAberturaForPeriod(start);
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

  void _openAccountSheet({
    required BuildContext context,
    required DateTime start,
    required DateTime end,
    required List<FinanceAccount> accounts,
    FinanceAccount? account,
    required double? openingBalanceHint,
  }) {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    FinanceAccountCategorySheetLauncher.show(
      context: context,
      uid: widget.uid,
      profile: widget.profile,
      from: start,
      to: end,
      account: account,
      openingBalanceHint: openingBalanceHint,
      financeAccounts: accounts,
      onOpenFinanceModule: widget.onOpenFinanceiro,
      nearlyFullScreen: true,
      // Lançamentos do período que o painel já tem: a tela abre pintada, sem
      // spinner, e confirma no servidor em segundo plano.
      initialDocs: _ultimosDocs[_chaveDocs(start, end)],
    );
  }

  void _openFinanceInsight({
    required BuildContext context,
    required FinanceInsightScope scope,
    required DateTime start,
    required DateTime end,
    String? financeAccountFilterId,
    String? financeAccountFilterLabel,
    double? openingBalanceHint,
    Map<String, double>? openingByAccountHint,
  }) {
    FinanceAccountCategorySheetLauncher.showInsight(
      context: context,
      uid: widget.uid,
      profile: widget.profile,
      scope: scope,
      from: start,
      to: end,
      financeAccountFilterId: financeAccountFilterId,
      financeAccountFilterLabel: financeAccountFilterLabel,
      openingBalanceHint: openingBalanceHint,
      openingByAccountHint: openingByAccountHint,
    );
  }

  @override
  Widget build(BuildContext context) {
    final (start, end) = _rangeForPeriod();
    final periodLabel = _periodLabel(start, end);
    final saldoAbertura = _saldoAberturaCached?.total ?? 0.0;
    final openingByAccount =
        _saldoAberturaCached?.byAccount ?? const <String, double>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _cabecalho(context, periodLabel),
        const SizedBox(height: 10),
        _seletorPeriodo(context, start, end),
        const SizedBox(height: 12),
        StreamBuilder<List<FinanceAccount>>(
          stream: _contasStream,
          initialData: _ultimasContas[_userFsId],
          builder: (context, accSnap) {
            final accounts = accSnap.data ?? const <FinanceAccount>[];
            final contasCarregando =
                accSnap.data == null && !accSnap.hasError && !_contasDemorou;
            return StreamBuilder<
                List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
              key: ValueKey('$_docsKey#$_tentativa'),
              stream: _docsStream,
              initialData: _ultimosDocs[_docsKey],
              builder: (context, txSnap) {
                final docs = txSnap.data ?? const [];
                final falhou = txSnap.data == null &&
                    (txSnap.hasError || _demorou);
                final carregando = txSnap.data == null && !falhou;
                double receitas = 0, despesas = 0, ajusteFora = 0;
                final despesasPagas = <Map<String, dynamic>>[];

                for (final doc in docs) {
                  final d = doc.data();
                  final type = (d['type'] ?? 'expense').toString();
                  if ((d['status'] ?? 'paid').toString() != 'paid') continue;
                  final amt = ((d['amount'] ?? 0) as num).toDouble().abs();
                  final effective =
                      FinanceLineOpening.effectiveDateTimeFromMap(d) ??
                          (d['date'] as Timestamp?)?.toDate();
                  if (effective == null) continue;
                  if (effective.isBefore(start) || effective.isAfter(end)) {
                    continue;
                  }
                  // Pagamento de fatura, transferência própria e reserva/
                  // resgate de meta: fora de receitas e despesas, mas o saldo
                  // continua igual (regra do Controle Total e do Financeiro).
                  if (financeForaDosTotais(d)) {
                    ajusteFora += type == 'income' ? amt : -amt;
                    continue;
                  }
                  if (type == 'income') {
                    receitas += amt;
                  } else {
                    despesas += amt;
                    despesasPagas.add(d);
                  }
                }

                final creditCardIds =
                    FinanceAccountBalanceUtils.creditCardAccountIds(accounts);
                final byAccPeriod =
                    FinanceAccountBalanceUtils.netPaidByAccountEffective(
                  docs: docs,
                  from: start,
                  to: end,
                  creditCardIds: creditCardIds,
                );
                final byAcc =
                    _mergeAccountBalances(openingByAccount, byAccPeriod);

                final saldoPeriodo = receitas - despesas + ajusteFora;
                final saldoAcum = saldoAbertura + saldoPeriodo;

                // «Evolução do Saldo»: só o pago, partindo da abertura real.
                final pontos = evolucaoDoSaldo(
                  abertura: saldoAbertura,
                  movimento: FinanceAccountBalanceUtils.movimentoDiarioPago(
                    items: docs.map((d) => d.data()),
                    from: start,
                    to: end,
                  ),
                  de: start,
                  ate: end,
                  hoje: DateTime.now(),
                );
                final spark = pontos.length >= 2
                    ? pontos.map((p) => p.saldo).toList()
                    : const <double>[];

                void abrirSaldo() => _openFinanceInsight(
                      context: context,
                      scope: FinanceInsightScope.balance,
                      start: start,
                      end: end,
                      openingBalanceHint: saldoAbertura,
                      openingByAccountHint: openingByAccount,
                    );
                void abrirEscopo(FinanceInsightScope s) => _openFinanceInsight(
                      context: context,
                      scope: s,
                      start: start,
                      end: end,
                      openingBalanceHint: saldoAbertura,
                      openingByAccountHint: openingByAccount,
                    );

                return LayoutBuilder(builder: (context, c) {
                  final largo = c.maxWidth >= 760;
                  final graficoSaldo =
                      _cardEvolucao(context, pontos, carregando);
                  final graficoCategorias = _cardCategorias(
                    context,
                    despesasPagas,
                    carregando,
                    onAbrir: () => abrirEscopo(FinanceInsightScope.expense),
                  );
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (falhou ||
                          ((accSnap.hasError || _contasDemorou) &&
                              accSnap.data == null)) ...[
                        _cardErroCarga(context),
                        const SizedBox(height: 12),
                      ],
                      _cardSaldo(
                        context,
                        periodLabel: periodLabel,
                        saldoAcum: saldoAcum,
                        saldoAbertura: saldoAbertura,
                        receitas: receitas,
                        despesas: despesas,
                        spark: spark,
                        carregando: carregando && docs.isEmpty,
                        largo: largo,
                        onSaldo: abrirSaldo,
                        onReceitas: () =>
                            abrirEscopo(FinanceInsightScope.income),
                        onDespesas: () =>
                            abrirEscopo(FinanceInsightScope.expense),
                      ),
                      const SizedBox(height: 14),
                      _tituloBloco(
                          context,
                          'Suas contas',
                          Icons.account_balance_rounded,
                          const Color(0xFF2563EB),
                          dica: accounts.isEmpty
                              ? null
                              : 'Toque numa conta para ver'),
                      const SizedBox(height: 8),
                      if (accounts.isEmpty && contasCarregando)
                        const SizedBox(
                          height: 128,
                          child: Center(
                            child: SizedBox(
                              width: 26,
                              height: 26,
                              child: CircularProgressIndicator(strokeWidth: 2.5),
                            ),
                          ),
                        )
                      else if (accounts.isEmpty)
                        _emptyAccountsCard()
                      else
                        SizedBox(
                          height: 128,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            physics: const BouncingScrollPhysics(),
                            children: [
                              _accountCard(
                                title: 'Todas as contas',
                                value: saldoAcum,
                                gradient: const [
                                  AppColors.primary,
                                  AppColors.deepBlue
                                ],
                                icon: Icons.dashboard_rounded,
                                onTap: () => _openAccountSheet(
                                  context: context,
                                  start: start,
                                  end: end,
                                  accounts: accounts,
                                  openingBalanceHint: saldoAbertura,
                                ),
                              ),
                              ...accounts.map((a) {
                                final vis = financeAccountVisualFor(a);
                                final accSaldo = byAcc[a.id] ??
                                    (openingByAccount[a.id] ?? 0);
                                return _accountCard(
                                  title: a.displayName,
                                  value: accSaldo,
                                  gradient: vis.gradient,
                                  icon: vis.icon,
                                  onTap: () => _openAccountSheet(
                                    context: context,
                                    start: start,
                                    end: end,
                                    accounts: accounts,
                                    account: a,
                                    openingBalanceHint: openingByAccount[a.id],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      if (widget.pendentesBuilder != null) ...[
                        const SizedBox(height: 16),
                        _tituloBloco(
                            context,
                            'Em aberto',
                            Icons.pending_actions_rounded,
                            const Color(0xFFEA580C)),
                        const SizedBox(height: 8),
                        widget.pendentesBuilder!(
                            context, accounts, _hideBalances),
                      ],
                      const SizedBox(height: 16),
                      _tituloBloco(context, 'Gráficos de $periodLabel',
                          Icons.insights_rounded, const Color(0xFF0E7490)),
                      const SizedBox(height: 8),
                      if (largo)
                        // Sem IntrinsicHeight: o gráfico de categorias usa
                        // LayoutBuilder, que não mede altura intrínseca.
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: graficoSaldo),
                            const SizedBox(width: 12),
                            Expanded(child: graficoCategorias),
                          ],
                        )
                      else ...[
                        graficoSaldo,
                        const SizedBox(height: 12),
                        graficoCategorias,
                      ],
                      const SizedBox(height: 12),
                      _botaoAbrirFinanceiro(context),
                    ],
                  );
                });
              },
            );
          },
        ),
      ],
    );
  }

  // ── Cabeçalho e período ───────────────────────────────────────────────────

  Widget _cabecalho(BuildContext context, String periodLabel) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF14532D), Color(0xFF15803D)],
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF15803D).withValues(alpha: 0.30),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.account_balance_wallet_rounded,
              color: Colors.white, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seu Financeiro',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                  color: context.appDeepTitle,
                ),
              ),
              Text(
                'Resumo de $periodLabel · toque em receitas, despesas ou contas',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: context.appTextSecondary,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: _hideBalances ? 'Mostrar valores' : 'Ocultar valores',
          onPressed: () async {
            final v = !_hideBalances;
            await SensitiveBalancePreferences.set(v);
            if (mounted) setState(() => _hideBalances = v);
          },
          icon: Icon(
            _hideBalances
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            color: context.isDarkMode ? context.appNeon : AppColors.primary,
          ),
        ),
      ],
    );
  }

  Widget _seletorPeriodo(BuildContext context, DateTime start, DateTime end) {
    final df = DateFormat('dd/MM/yy', 'pt_BR');
    Widget botaoData({
      required String rotulo,
      required IconData icone,
      required DateTime inicial,
      required DateTime primeira,
      required void Function(DateTime) aoEscolher,
    }) {
      final cor = context.isDarkMode ? context.appNeon : AppColors.primary;
      return Expanded(
        child: FilledButton.tonalIcon(
          onPressed: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: inicial,
              firstDate: primeira,
              lastDate: DateTime(2030),
            );
            if (picked != null && mounted) aoEscolher(picked);
          },
          icon: Icon(icone, size: 16),
          label: Text(rotulo,
              style:
                  const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
          style: FilledButton.styleFrom(
            foregroundColor: cor,
            backgroundColor: cor.withValues(alpha: 0.1),
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          child: Row(
            children: _periods.map((p) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _periodChip(
                  period: p,
                  selected: _selectedPeriod == p,
                  onSelect: () => _applyPeriod(p),
                ),
              );
            }).toList(),
          ),
        ),
        if (_selectedPeriod == 'Por período') ...[
          const SizedBox(height: 8),
          Row(
            children: [
              botaoData(
                rotulo: 'De ${df.format(_customRangeStart ?? start)}',
                icone: Icons.calendar_today_rounded,
                inicial: _customRangeStart ?? start,
                primeira: DateTime(2000),
                aoEscolher: (d) {
                  _customRangeStart = d;
                  _periodoPersonalizadoMudou();
                },
              ),
              const SizedBox(width: 8),
              botaoData(
                rotulo: 'Até ${df.format(_customRangeEnd ?? end)}',
                icone: Icons.event_rounded,
                inicial: _customRangeEnd ?? end,
                primeira: _customRangeStart ?? DateTime(2000),
                aoEscolher: (d) {
                  _customRangeEnd = d;
                  _periodoPersonalizadoMudou();
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _periodChip({
    required String period,
    required bool selected,
    required VoidCallback onSelect,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onSelect,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFF14532D), Color(0xFF15803D)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: selected ? null : context.appChipIdleBg,
            border: Border.all(
              color: selected ? Colors.transparent : context.appChipIdleBorder,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: const Color(0xFF14532D).withValues(alpha: 0.22),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Text(
            period,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: selected
                  ? Colors.white
                  : (context.isDarkMode
                      ? context.appChipIdleLabel
                      : const Color(0xFF14532D)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _tituloBloco(
    BuildContext context,
    String titulo,
    IconData icone,
    Color cor, {
    String? dica,
  }) {
    return Row(
      children: [
        Icon(icone, size: 18, color: cor),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            titulo,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w900,
              color: context.appTextPrimary,
            ),
          ),
        ),
        if (dica != null)
          Text(
            dica,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: context.appTextMuted),
          ),
      ],
    );
  }

  // ── Card do saldo (receitas × despesas) ───────────────────────────────────

  Widget _cardSaldo(
    BuildContext context, {
    required String periodLabel,
    required double saldoAcum,
    required double saldoAbertura,
    required double receitas,
    required double despesas,
    required List<double> spark,
    required bool carregando,
    required bool largo,
    required VoidCallback onSaldo,
    required VoidCallback onReceitas,
    required VoidCallback onDespesas,
  }) {
    final totalMov = receitas + despesas;
    final fracRec = totalMov > 0 ? receitas / totalMov : 0.5;
    final saldoPeriodo = receitas - despesas;

    final saldoTile = _metricTile(
      'Saldo acumulado',
      saldoAcum,
      saldoAcum >= 0 ? AppColors.saldoPositive : AppColors.saldoNegative,
      hint: 'Gráficos e lançamentos',
      onTap: onSaldo,
      grande: true,
      carregando: carregando,
    );
    final recTile = _metricTile(
      'Receitas',
      receitas,
      AppColors.saldoPositive,
      hint: 'Ver e editar',
      icone: Icons.arrow_downward_rounded,
      onTap: onReceitas,
      carregando: carregando,
    );
    final despTile = _metricTile(
      'Despesas',
      despesas,
      AppColors.saldoNegative,
      hint: 'Ver e editar',
      icone: Icons.arrow_upward_rounded,
      onTap: onDespesas,
      carregando: carregando,
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          colors: [Color(0xFF14532D), Color(0xFF166534), Color(0xFF15803D)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.saldoPositive.withValues(alpha: 0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.calendar_month_rounded,
                  size: 16, color: Colors.white.withValues(alpha: 0.9)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  periodLabel,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.92),
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
              Text(
                'Abertura ${SensitiveBalancePreferences.formatBrl(saldoAbertura, hidden: _hideBalances)}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (largo)
            Row(
              children: [
                Expanded(flex: 4, child: saldoTile),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: recTile),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: despTile),
              ],
            )
          else ...[
            saldoTile,
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: recTile),
                const SizedBox(width: 8),
                Expanded(child: despTile),
              ],
            ),
          ],
          const SizedBox(height: 12),
          // Receitas × despesas do período numa barra só.
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Expanded(
                    flex: math.max(1, (fracRec * 1000).round()),
                    child: Container(color: const Color(0xFF86EFAC)),
                  ),
                  Expanded(
                    flex: math.max(1, ((1 - fracRec) * 1000).round()),
                    child: Container(color: const Color(0xFFFCA5A5)),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _hideBalances
                ? 'Resultado do período oculto'
                : saldoPeriodo >= 0
                    ? 'Sobrou ${CurrencyFormats.formatBRL(saldoPeriodo)} no período'
                    : 'Faltou ${CurrencyFormats.formatBRL(saldoPeriodo.abs())} no período',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontWeight: FontWeight.w700,
              fontSize: 11.5,
            ),
          ),
          if (spark.length >= 2) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FinanceSparkline(
                values: spark,
                color: Colors.white.withValues(alpha: 0.9),
                height: 36,
                width: double.infinity,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: widget.onOpenFinanceiro,
              icon: Icon(
                Icons.open_in_new_rounded,
                size: 16,
                color: Colors.white.withValues(alpha: 0.92),
              ),
              label: Text(
                'Abrir Financeiro',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.92),
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricTile(
    String label,
    double value,
    Color color, {
    String? hint,
    IconData? icone,
    VoidCallback? onTap,
    bool grande = false,
    bool carregando = false,
  }) {
    final dark = context.isDarkMode;
    final fundo = dark ? context.appDarkModuleSurface : Colors.white;
    final corValor = dark ? Color.lerp(color, Colors.white, 0.25)! : color;
    final tile = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fundo,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icone != null) ...[
                Icon(icone, size: 14, color: corValor),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: corValor,
                  ),
                ),
              ),
            ],
          ),
          if (hint != null && onTap != null) ...[
            const SizedBox(height: 2),
            Text(
              hint,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                color: corValor.withValues(alpha: 0.72),
              ),
            ),
          ],
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              carregando
                  ? '…'
                  : SensitiveBalancePreferences.formatBrl(value,
                      hidden: _hideBalances),
              style: TextStyle(
                fontSize: grande ? 22 : 16,
                fontWeight: FontWeight.w900,
                color: corValor,
              ),
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return tile;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: tile,
      ),
    );
  }

  // ── Carrossel de contas ───────────────────────────────────────────────────

  Widget _accountCard({
    required String title,
    required double value,
    required List<Color> gradient,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final negativo = value < 0;
    return Padding(
      padding: const EdgeInsets.only(right: 10, bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Ink(
            width: 160,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: LinearGradient(
                colors: gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: gradient.first.withValues(alpha: 0.30),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: Colors.white, size: 18),
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded,
                        color: Colors.white.withValues(alpha: 0.8), size: 18),
                  ],
                ),
                const Spacer(),
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    SensitiveBalancePreferences.formatBrl(value,
                        hidden: _hideBalances),
                    style: TextStyle(
                      color: negativo && !_hideBalances
                          ? const Color(0xFFFECACA)
                          : Colors.white.withValues(alpha: 0.95),
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
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

  Widget _emptyAccountsCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: context.appPanelDecoration(radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Cadastre bancos e cartões para ver saldos e gráficos aqui.',
            style: TextStyle(
                fontSize: 13, height: 1.35, color: context.appTextPrimary),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: widget.onOpenFinanceiro,
            icon: const Icon(Icons.add_card_rounded),
            label: const Text('Abrir Financeiro'),
          ),
        ],
      ),
    );
  }

  // ── Gráficos ──────────────────────────────────────────────────────────────

  Widget _cardGrafico(
    BuildContext context, {
    required String titulo,
    required IconData icone,
    required Color cor,
    required Widget child,
    Widget? acao,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: context.appChartCardDecoration(radius: 20, accent: cor),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: cor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icone, size: 18, color: cor),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                titulo,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w900,
                  color: context.appTextPrimary,
                ),
              ),
            ),
            if (acao != null) acao,
          ]),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _cardEvolucao(
    BuildContext context,
    List<({DateTime dia, double saldo})> pontos,
    bool carregando,
  ) {
    const cor = Color(0xFF0E7490);
    Widget corpo;
    if (pontos.length < 2) {
      corpo = SizedBox(
        height: 180,
        child: Center(
          child: Text(
            carregando
                ? 'Carregando…'
                : 'Ainda não há dias suficientes no período.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: context.appTextSecondary),
          ),
        ),
      );
    } else if (_hideBalances) {
      corpo = SizedBox(
        height: 180,
        child: Center(
          child: Text(
            'Valores ocultos — toque no olho para mostrar.',
            style: TextStyle(fontSize: 13, color: context.appTextSecondary),
          ),
        ),
      );
    } else {
      final valores = pontos.map((p) => p.saldo).toList();
      final menor = valores.reduce(math.min);
      final maior = valores.reduce(math.max);
      final folga = ((maior - menor).abs() * 0.15) + 1;
      final linha = context.isDarkMode ? context.appNeon : cor;
      corpo = SizedBox(
        height: 190,
        child: LineChart(
          LineChartData(
            minY: menor - folga,
            maxY: maior + folga,
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: context.appBorderSubtle, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              leftTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              topTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 22,
                  interval: math.max(1, (pontos.length / 4).floorToDouble()),
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= pontos.length) {
                      return const SizedBox.shrink();
                    }
                    final d = pontos[i].dia;
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${d.day}/${d.month}',
                        style: TextStyle(
                            fontSize: 10, color: context.appTextSecondary),
                      ),
                    );
                  },
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipItems: (spots) => spots.map((s) {
                  final p = pontos[s.x.toInt()];
                  return LineTooltipItem(
                    '${p.dia.day}/${p.dia.month}\n${CurrencyFormats.formatBRL(p.saldo)}',
                    const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 11),
                  );
                }).toList(),
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                spots: [
                  for (var i = 0; i < pontos.length; i++)
                    FlSpot(i.toDouble(), pontos[i].saldo),
                ],
                isCurved: true,
                curveSmoothness: 0.22,
                color: linha,
                barWidth: 2.6,
                dotData: const FlDotData(show: false),
                belowBarData: BarAreaData(
                  show: true,
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      linha.withValues(alpha: 0.28),
                      linha.withValues(alpha: 0.0)
                    ],
                  ),
                ),
              ),
            ],
          ),
          duration: Duration.zero,
        ),
      );
    }
    final ultimo = pontos.isEmpty ? null : pontos.last;
    return _cardGrafico(
      context,
      titulo: 'Evolução do Saldo',
      icone: Icons.trending_up_rounded,
      cor: cor,
      acao: ultimo == null || _hideBalances
          ? null
          : Text(
              CurrencyFormats.formatBRL(ultimo.saldo),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w900,
                color: ultimo.saldo >= 0 ? _kVerde : _kVermelho,
              ),
            ),
      child: RepaintBoundary(child: corpo),
    );
  }

  Widget _cardCategorias(
    BuildContext context,
    List<Map<String, dynamic>> despesasPagas,
    bool carregando, {
    required VoidCallback onAbrir,
  }) {
    const cor = Color(0xFF7C3AED);
    final fatias = agruparCategorias(despesasPagas);
    return _cardGrafico(
      context,
      titulo: 'Despesas por categoria',
      icone: Icons.pie_chart_rounded,
      cor: cor,
      child: _hideBalances
          ? SizedBox(
              height: 120,
              child: Center(
                child: Text(
                  'Valores ocultos — toque no olho para mostrar.',
                  style:
                      TextStyle(fontSize: 13, color: context.appTextSecondary),
                ),
              ),
            )
          : RepaintBoundary(
              child: CategoriasRoscaModerna(
                fatias: fatias,
                titulo: 'Despesas',
                textoVazio: carregando
                    ? 'Carregando…'
                    : 'Nenhuma despesa paga no período',
                onAbrir: (_) => onAbrir(),
              ),
            ),
    );
  }

  Widget _botaoAbrirFinanceiro(BuildContext context) {
    return FilledButton.icon(
      onPressed: widget.onOpenFinanceiro,
      icon: const Icon(Icons.account_balance_wallet_rounded),
      label: const Text('Ir para o Financeiro'),
      style: FilledButton.styleFrom(
        backgroundColor:
            context.isDarkMode ? context.appNeon : const Color(0xFF15803D),
        foregroundColor: context.isDarkMode ? context.appNeonOn : Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w900),
      ),
    );
  }

  String _monthName(int m) {
    const names = [
      'Janeiro',
      'Fevereiro',
      'Março',
      'Abril',
      'Maio',
      'Junho',
      'Julho',
      'Agosto',
      'Setembro',
      'Outubro',
      'Novembro',
      'Dezembro',
    ];
    return names[m - 1];
  }
}
