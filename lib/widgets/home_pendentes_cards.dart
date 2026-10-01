import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/app_business_rules.dart';
import '../constants/currency_formats.dart';
import '../models/finance_account.dart';
import '../models/user_profile.dart';
import '../services/fixed_expense_preferences_service.dart';
import '../services/fixed_income_preferences_service.dart';
import '../services/sensitive_balance_preferences.dart';
import '../theme/theme_context.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/finance_transactions_realtime.dart';
import '../utils/home_painel_resumo.dart';
import '../utils/premium_upgrade.dart';
import 'finance_confirm_payment_sheet.dart';
import 'fixas_a_pagar_painel.dart';
import 'fixas_visao_geral.dart';

const _kAzulRec = Color(0xFF0EA5E9);
const _kAzulRecEscuro = Color(0xFF0284C7);
const _kLaranja = Color(0xFFF97316);
const _kLaranjaEscuro = Color(0xFFEA580C);
const _kVermelho = Color(0xFFDC2626);
const _kVerde = Color(0xFF16A34A);

/// Últimos pendentes por usuário — o painel desmonta ao trocar de módulo
/// (celular: um módulo por vez) e, ao voltar, pinta na hora com o último
/// valor bom em vez de ficar em branco esperando o Firestore.
final Map<String, QuerySnapshot<Map<String, dynamic>>> _ultimoRec = {};
final Map<String, QuerySnapshot<Map<String, dynamic>>> _ultimoDesp = {};
final Map<String, Map<String, dynamic>> _ultimaPrefRec = {};
final Map<String, Map<String, dynamic>> _ultimaPrefDesp = {};

/// Cards «Receitas pendentes» / «Despesas pendentes» + «Contas fixas do mês»
/// do painel inicial (padrão Controle Total).
///
/// Estável na Web: cada consulta é assinada UMA vez (nada de `.snapshots()`
/// no build); se a escuta cair, segue mostrando o último valor bom e
/// reconecta sozinho em 2/4/8/16 s (igual ao Financeiro).
class HomePendentesSecao extends StatefulWidget {
  const HomePendentesSecao({
    super.key,
    required this.uid,
    required this.profile,
    required this.contas,
    required this.ocultarValores,
    this.onAbrirFinanceiro,
  });

  /// Id do documento do usuário no Firestore (o mesmo do shell).
  final String uid;
  final UserProfile profile;
  final List<FinanceAccount> contas;
  final bool ocultarValores;
  final VoidCallback? onAbrirFinanceiro;

  @override
  State<HomePendentesSecao> createState() => _HomePendentesSecaoState();
}

class _HomePendentesSecaoState extends State<HomePendentesSecao> {
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subRec;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subDesp;
  StreamSubscription<Map<String, dynamic>>? _subPrefRec;
  StreamSubscription<Map<String, dynamic>>? _subPrefDesp;

  final ValueNotifier<PendentesResumo> _rec =
      ValueNotifier(PendentesResumo.vazio);
  final ValueNotifier<PendentesResumo> _desp =
      ValueNotifier(PendentesResumo.vazio);
  FixasMesResumo _fixasPagar = FixasMesResumo.vazio;
  FixasMesResumo _fixasReceber = FixasMesResumo.vazio;

  Timer? _retry;
  int _tentativas = 0;
  String? _erroSemDados;

  String get _uid => widget.uid;

  Set<String> get _cartoes => widget.contas
      .where((a) => a.isCreditCardProduct)
      .map((a) => a.id)
      .toSet();

  @override
  void initState() {
    super.initState();
    _recalcular(rebuild: false);
    // Depois do 1º quadro: não disputa a primeira pintura do Início.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _subRec == null) _abrirEscutas();
    });
  }

  @override
  void didUpdateWidget(covariant HomePendentesSecao oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uid != widget.uid) {
      _fecharEscutas();
      _recalcular(rebuild: false);
      _abrirEscutas();
      return;
    }
    if (oldWidget.contas != widget.contas) _recalcular(rebuild: false);
  }

  @override
  void dispose() {
    _retry?.cancel();
    _fecharEscutas();
    _rec.dispose();
    _desp.dispose();
    super.dispose();
  }

  Query<Map<String, dynamic>> _pendentes(String tipo) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(_uid)
          .collection('transactions')
          .where('type', isEqualTo: tipo)
          .where('status', isEqualTo: 'pending')
          .orderBy('date', descending: false)
          .limit(kFinancePendingStreamLimit);

  void _abrirEscutas() {
    if (_uid.isEmpty) return;
    _subRec =
        _pendentes('income').snapshots(includeMetadataChanges: false).listen(
      (s) {
        _ultimoRec[_uid] = s;
        _tentativas = 0;
        _erroSemDados = null;
        _recalcular();
      },
      onError: _onErro,
    );
    _subDesp =
        _pendentes('expense').snapshots(includeMetadataChanges: false).listen(
      (s) {
        _ultimoDesp[_uid] = s;
        _tentativas = 0;
        _erroSemDados = null;
        _recalcular();
      },
      onError: _onErro,
    );
    _subPrefRec = FixedIncomePreferencesService().watch(_uid).listen((v) {
      _ultimaPrefRec[_uid] = v;
      _recalcular();
    }, onError: (_) {});
    _subPrefDesp = FixedExpensePreferencesService().watch(_uid).listen((v) {
      _ultimaPrefDesp[_uid] = v;
      _recalcular();
    }, onError: (_) {});
  }

  void _fecharEscutas() {
    _subRec?.cancel();
    _subDesp?.cancel();
    _subPrefRec?.cancel();
    _subPrefDesp?.cancel();
    _subRec = _subDesp = null;
    _subPrefRec = _subPrefDesp = null;
  }

  /// Escuta caiu: mantém o último valor bom e tenta de novo (2, 4, 8, 16 s).
  /// `permission-denied` é sessão — não adianta insistir.
  void _onErro(Object erro) {
    final semDados = _ultimoRec[_uid] == null && _ultimoDesp[_uid] == null;
    if (semDados && mounted) {
      setState(() =>
          _erroSemDados = 'Não foi possível carregar os pendentes agora.');
    }
    if ('$erro'.contains('permission-denied')) return;
    if (_retry != null || _tentativas >= 4) return;
    final espera = Duration(seconds: 2 << _tentativas);
    _tentativas++;
    _retry = Timer(espera, () {
      _retry = null;
      if (!mounted) return;
      _subRec?.cancel();
      _subDesp?.cancel();
      _subPrefRec?.cancel();
      _subPrefDesp?.cancel();
      _abrirEscutas();
    });
  }

  void _recalcular({bool rebuild = true}) {
    final hoje = DateTime.now();
    final cartoes = _cartoes;
    PendentesResumo resumo(
      QuerySnapshot<Map<String, dynamic>>? snap,
      Map<String, dynamic>? prefs,
      String campo,
    ) {
      if (snap == null) return PendentesResumo.vazio;
      final mostrar = prefs?['showInPending'] as bool? ?? true;
      final meses = (prefs?['pendingMonthsAhead'] as int?)?.clamp(0, 12) ??
          AppBusinessRules.pendingMonthsAheadDefault;
      return resumirPendentes(
        docs: snap.docs.map((d) => (id: d.id, data: d.data())),
        hoje: hoje,
        mesesAFrente: meses,
        mostrarFixas: mostrar,
        campoFixa: campo,
        contasCartao: cartoes,
      );
    }

    final snapRec = _ultimoRec[_uid];
    final snapDesp = _ultimoDesp[_uid];
    _rec.value = resumo(snapRec, _ultimaPrefRec[_uid], 'fixedIncomeId');
    _desp.value = resumo(snapDesp, _ultimaPrefDesp[_uid], 'fixedExpenseId');
    _fixasPagar = resumirFixasDoMes(
      pendentes: (snapDesp?.docs ?? const []).map((d) => d.data()),
      hoje: hoje,
      campoFixa: 'fixedExpenseId',
      contasCartao: cartoes,
    );
    _fixasReceber = resumirFixasDoMes(
      pendentes: (snapRec?.docs ?? const []).map((d) => d.data()),
      hoje: hoje,
      campoFixa: 'fixedIncomeId',
      contasCartao: cartoes,
    );
    if (rebuild && mounted) setState(() {});
  }

  bool get _temDados => _ultimoRec[_uid] != null || _ultimoDesp[_uid] != null;

  String _valor(double v) {
    if (!_temDados) return '…';
    return SensitiveBalancePreferences.formatBrl(v,
        hidden: widget.ocultarValores);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final largo = c.maxWidth >= 620;
      final rec = ValueListenableBuilder<PendentesResumo>(
        valueListenable: _rec,
        builder: (context, r, _) => _cardPendente(
          context,
          receita: true,
          resumo: r,
        ),
      );
      final desp = ValueListenableBuilder<PendentesResumo>(
        valueListenable: _desp,
        builder: (context, r, _) => _cardPendente(
          context,
          receita: false,
          resumo: r,
        ),
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_erroSemDados != null && !_temDados)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration:
                    context.appInfoBannerDecoration(_kLaranja, radius: 12),
                child: Row(children: [
                  const Icon(Icons.wifi_off_rounded,
                      size: 18, color: _kLaranjaEscuro),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_erroSemDados!} Tentando de novo…',
                      style: TextStyle(
                          fontSize: 12, color: context.appTextSecondary),
                    ),
                  ),
                ]),
              ),
            ),
          if (largo)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: rec),
                const SizedBox(width: 12),
                Expanded(child: desp),
              ],
            )
          else ...[
            rec,
            const SizedBox(height: 10),
            desp,
          ],
          const SizedBox(height: 12),
          _cardFixas(context),
        ],
      );
    });
  }

  Widget _cardPendente(
    BuildContext context, {
    required bool receita,
    required PendentesResumo resumo,
  }) {
    final cores = receita
        ? const [_kAzulRec, _kAzulRecEscuro]
        : const [_kLaranja, _kLaranjaEscuro];
    final titulo = receita ? 'Receitas pendentes' : 'Despesas pendentes';
    final sub = !_temDados
        ? 'Carregando…'
        : resumo.quantidade == 0
            ? 'Nada em aberto · Toque para ver'
            : '${resumo.quantidade} lançamento(s) em aberto · Toque para ver';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _abrirLista(receita: receita),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              colors: [
                cores.first,
                cores.first.withValues(alpha: 0.9),
                cores.last
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: cores.first.withValues(alpha: 0.32),
                blurRadius: 14,
                offset: const Offset(0, 5),
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
                child: Icon(
                  receita
                      ? Icons.call_received_rounded
                      : Icons.call_made_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.88),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  _valor(resumo.total),
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
  }

  Widget _cardFixas(BuildContext context) {
    final mes = nomeDoMes(DateTime.now().month);
    Widget lado({
      required bool receita,
      required FixasMesResumo r,
    }) {
      final cor = receita ? _kVerde : _kVermelho;
      final linha = !_temDados
          ? 'Carregando…'
          : r.emAberto == 0
              ? (receita ? 'Tudo recebido' : 'Tudo pago')
              : [
                  if (r.vencidas > 0) '${r.vencidas} vencida(s)',
                  if (r.aVencer > 0) '${r.aVencer} a vencer',
                ].join(' · ');
      return Expanded(
        child: Material(
          color:
              context.appAccentSurface(cor, lightAlpha: 0.07, darkAlpha: 0.16),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => _abrirFixasAPagar(receita: receita),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(
                      receita
                          ? Icons.savings_rounded
                          : Icons.event_note_rounded,
                      size: 18,
                      color: cor,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        receita ? 'A receber' : 'A pagar',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w900,
                          color: cor,
                        ),
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, size: 18, color: cor),
                  ]),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _valor(r.totalEmAberto),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: context.appTextPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    linha,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: r.vencidas > 0
                          ? _kVermelho
                          : context.appTextSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: context.appPanelDecoration(
          radius: 18, borderAccent: _kVermelho, borderAlpha: 0.14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFF7C3AED), Color(0xFFDB2777)]),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.repeat_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Contas fixas de $mes',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w900,
                        color: context.appTextPrimary,
                      ),
                    ),
                    Text(
                      'O que tenho que pagar e receber no mês',
                      style: TextStyle(
                          fontSize: 11.5, color: context.appTextSecondary),
                    ),
                  ]),
            ),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            lado(receita: false, r: _fixasPagar),
            const SizedBox(width: 10),
            lado(receita: true, r: _fixasReceber),
          ]),
        ],
      ),
    );
  }

  // ── Folhas ──────────────────────────────────────────────────────────────

  void _abrirFixasAPagar({required bool receita}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.35,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scroll) => DecoratedBox(
          decoration:
              ctx.appSheetDecoration(tint: receita ? _kVerde : _kVermelho),
          child: ListView(
            controller: scroll,
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              const _AlcaFolha(),
              FixasAPagarPainel(uid: _uid, receita: receita),
              if (widget.onAbrirFinanceiro != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      widget.onAbrirFinanceiro!();
                    },
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Abrir Financeiro'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _abrirLista({required bool receita}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.3,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, scroll) => DecoratedBox(
          decoration:
              ctx.appSheetDecoration(tint: receita ? _kAzulRec : _kLaranja),
          child: ValueListenableBuilder<PendentesResumo>(
            valueListenable: receita ? _rec : _desp,
            builder: (ctx, r, _) => _ListaPendentes(
              scroll: scroll,
              receita: receita,
              resumo: r,
              ocultarValores: widget.ocultarValores,
              cabecalho: FixasVisaoGeral(
                uid: _uid,
                receita: receita,
                pendentes: true,
                excluirContas: _cartoes,
                margem: const EdgeInsets.only(bottom: 14),
              ),
              onPagar: (item) => _pagar(item, receita: receita),
              onAbrirFinanceiro: widget.onAbrirFinanceiro == null
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      widget.onAbrirFinanceiro!();
                    },
            ),
          ),
        ),
      ),
    );
  }

  final Set<String> _ocupados = {};

  /// O mesmo «Confirmar pagamento» do Financeiro (entra no saldo).
  Future<bool> _pagar(Map<String, dynamic> item,
      {required bool receita}) async {
    if (!widget.profile.hasActiveLicense) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return false;
    }
    final id = (item['id'] ?? '').toString();
    if (id.isEmpty || _ocupados.contains(id)) return false;
    final contaId = (item['financeAccountId'] ?? '').toString().trim();
    final valor = ((item['amount'] as num?) ?? 0).toDouble().abs();
    final desc = (item['description'] ?? '').toString().trim();
    final r = await showFinanceConfirmPaymentSheet(
      context: context,
      isIncome: receita,
      financeAccounts: widget.contas,
      initialFinanceAccountId: contaId.isEmpty ? null : contaId,
      orphanAccountId: contaId,
      amountPreview: valor,
      categoryPreview: (item['category'] ?? '').toString(),
      descriptionPreview: desc,
    );
    if (r == null || !mounted) return false;
    _ocupados.add(id);
    try {
      await commitFinanceConfirmPayment(
        txRef: FirebaseFirestore.instance
            .collection('users')
            .doc(_uid)
            .collection('transactions')
            .doc(id),
        uid: _uid,
        result: r,
      );
      final venc = item['date'];
      FinanceTransactionsHub.notifyMutated(
        uid: _uid,
        effectiveDate: venc is Timestamp ? venc.toDate() : r.paymentDate,
      );
      _snack(receita ? 'Recebimento confirmado.' : 'Pagamento confirmado.');
      return true;
    } catch (e) {
      _snack('Erro ao confirmar: ${e.toString().split('\n').first}',
          erro: true);
      return false;
    } finally {
      _ocupados.remove(id);
    }
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: erro ? _kVermelho : null,
      ),
    );
  }
}

class _AlcaFolha extends StatelessWidget {
  const _AlcaFolha();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        width: 42,
        height: 4,
        decoration: BoxDecoration(
          color: context.appBorderSubtle,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}

/// Lista dos pendentes (folha aberta pelos cards), com Pagar/Receber em cada.
class _ListaPendentes extends StatefulWidget {
  const _ListaPendentes({
    required this.scroll,
    required this.receita,
    required this.resumo,
    required this.ocultarValores,
    required this.cabecalho,
    required this.onPagar,
    this.onAbrirFinanceiro,
  });

  final ScrollController scroll;
  final bool receita;
  final PendentesResumo resumo;
  final bool ocultarValores;
  final Widget cabecalho;
  final Future<bool> Function(Map<String, dynamic> item) onPagar;
  final VoidCallback? onAbrirFinanceiro;

  @override
  State<_ListaPendentes> createState() => _ListaPendentesState();
}

class _ListaPendentesState extends State<_ListaPendentes> {
  final Set<String> _pagando = {};

  static String _ddmm(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final cor = widget.receita ? _kAzulRecEscuro : _kLaranjaEscuro;
    final itens = widget.resumo.itens;
    return ListView(
      controller: widget.scroll,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        const _AlcaFolha(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(children: [
            Icon(
              widget.receita
                  ? Icons.call_received_rounded
                  : Icons.call_made_rounded,
              color: cor,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.receita ? 'Receitas pendentes' : 'Despesas pendentes',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: context.appTextPrimary,
                ),
              ),
            ),
            Text(
              SensitiveBalancePreferences.formatBrl(
                widget.resumo.total,
                hidden: widget.ocultarValores,
              ),
              style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w900, color: cor),
            ),
          ]),
        ),
        widget.cabecalho,
        if (itens.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                widget.receita
                    ? 'Nenhuma receita pendente'
                    : 'Nenhuma despesa pendente',
                style: TextStyle(
                    color: context.appTextSecondary,
                    fontWeight: FontWeight.w600),
              ),
            ),
          )
        else
          for (final item in itens) _linha(context, item, cor),
        if (widget.onAbrirFinanceiro != null) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: widget.onAbrirFinanceiro,
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Ver tudo no Financeiro'),
          ),
        ],
      ],
    );
  }

  Widget _linha(BuildContext context, Map<String, dynamic> item, Color cor) {
    final id = (item['id'] ?? '').toString();
    final ts = item['date'];
    final data = ts is Timestamp ? ts.toDate() : null;
    final desc = (item['description'] ?? '').toString().trim();
    final cat = (item['category'] ?? '').toString().trim();
    final valor = ((item['amount'] as num?) ?? 0).toDouble().abs();
    final ocupado = _pagando.contains(id);
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: context.appPanelDecoration(
          radius: 14, borderAccent: cor, borderAlpha: 0.14),
      child: Row(children: [
        Expanded(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              desc.isNotEmpty ? desc : (cat.isNotEmpty ? cat : 'Lançamento'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13.5,
                color: context.appTextPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (data != null) 'Vence ${_ddmm(data)}',
                if (cat.isNotEmpty && desc.isNotEmpty) cat,
              ].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11.5, color: context.appTextSecondary),
            ),
          ]),
        ),
        const SizedBox(width: 8),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            widget.ocultarValores
                ? SensitiveBalancePreferences.formatBrl(valor, hidden: true)
                : CurrencyFormats.formatBRL(valor),
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 14, color: cor),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 30,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
              ),
              onPressed: ocupado
                  ? null
                  : () async {
                      setState(() => _pagando.add(id));
                      await widget.onPagar(item);
                      if (mounted) setState(() => _pagando.remove(id));
                    },
              child: ocupado
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(widget.receita ? 'Receber' : 'Pagar'),
            ),
          ),
        ]),
      ]),
    );
  }
}
