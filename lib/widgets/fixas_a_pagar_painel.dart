import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../models/finance_account.dart';
import '../services/finance_accounts_service.dart';
import '../theme/theme_context.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/finance_transactions_realtime.dart';
import '../utils/firestore_user_doc_id.dart';
import 'finance_confirm_payment_sheet.dart';
import 'finance_load_error_box.dart';

const _kVermelho = Color(0xFFDC2626);
const _kLaranja = Color(0xFFEA580C);
const _kAzul = Color(0xFF2563EB);
const _kVerde = Color(0xFF16A34A);

String _ddmm(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

const _meses = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

/// Uma fixa do mês, pronta para a tela.
class _FixaItem {
  _FixaItem(this.id, this.d, this.venc, this.valor, this.contaNome);
  final String id;
  final Map<String, dynamic> d;
  final DateTime venc;
  final double valor;
  final String contaNome;

  bool get pago => (d['status'] ?? 'paid').toString() == 'paid';
  String get descricao {
    final s = (d['description'] ?? '').toString().trim();
    if (s.isNotEmpty) return s;
    final c = (d['category'] ?? '').toString().trim();
    return c.isEmpty ? 'Conta fixa' : c;
  }

  DateTime? get pagoEm {
    final p = d['paidAt'];
    return p is Timestamp ? p.toDate() : null;
  }
}

/// «O que tenho que pagar» no topo de Despesas fixas (e «a receber» nas
/// Receitas fixas): as fixas do mês em 🔴 vencidas · 🟠 vencem em até 7 dias
/// · ainda este mês · 🟢 pagas, com o botão de pagar em cada uma.
///
/// WISDOMAPP: sem Finance Pro (banco conectado) — pagar usa sempre o mesmo
/// «Confirmar pagamento» do Financeiro (entra no saldo).
class FixasAPagarPainel extends StatefulWidget {
  const FixasAPagarPainel({super.key, required this.uid, required this.receita});

  final String uid;
  final bool receita;

  @override
  State<FixasAPagarPainel> createState() => _FixasAPagarPainelState();
}

class _FixasAPagarPainelState extends State<FixasAPagarPainel> {
  late Stream<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _docs;
  late final Stream<List<FinanceAccount>> _contas;
  late final DateTime _rangeStart;
  late final DateTime _rangeEnd;

  /// Passou do prazo sem resposta: mostra «Tentar de novo» (antes era só o
  /// pontinho carregando para sempre).
  bool _demorou = false;
  Timer? _prazo;
  late final DateTime _hoje;
  late final DateTime _fimMes;
  bool _verPagas = false;
  final Set<String> _ocupados = {};

  Color get _cor => widget.receita ? _kVerde : _kVermelho;
  String get _campo => widget.receita ? 'fixedIncomeId' : 'fixedExpenseId';

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _hoje = DateTime(n.year, n.month, n.day);
    _fimMes = DateTime(n.year, n.month + 1, 0, 23, 59, 59);
    final seteDias = _hoje.add(const Duration(days: 7, hours: 23, minutes: 59));
    // Dois meses para trás: conta do mês passado que ficou sem pagar ainda é
    // «vencida» — sumir com ela só porque virou o mês esconderia a dívida.
    _rangeStart = DateTime(n.year, n.month - 2, 1);
    _rangeEnd = seteDias.isAfter(_fimMes) ? seteDias : _fimMes;
    _docs = financeTransactionsPeriodDocs(
      uid: widget.uid,
      rangeStart: _rangeStart,
      rangeEnd: _rangeEnd,
    );
    _contas = FinanceAccountsService().streamAccounts(widget.uid);
    _armarPrazo();
  }

  void _armarPrazo() {
    _prazo?.cancel();
    _demorou = false;
    _prazo = Timer(const Duration(seconds: 20), () {
      if (mounted) setState(() => _demorou = true);
    });
  }

  void _tentarDeNovo() {
    setState(() {
      _docs = financeTransactionsPeriodDocs(
        uid: widget.uid,
        rangeStart: _rangeStart,
        rangeEnd: _rangeEnd,
        renovar: true,
      );
      _armarPrazo();
    });
  }

  @override
  void dispose() {
    _prazo?.cancel();
    super.dispose();
  }

  List<_FixaItem> _itens(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    List<FinanceAccount> contas,
  ) {
    final porId = {for (final c in contas) c.id: c};
    final tipo = widget.receita ? 'income' : 'expense';
    final vistos = <String>{};
    final out = <_FixaItem>[];
    for (final doc in docs) {
      if (!vistos.add(doc.id)) continue;
      final d = doc.data();
      if ((d[_campo] ?? '').toString().trim().isEmpty) continue;
      if ((d['type'] ?? '').toString() != tipo) continue;
      final contaId = (d['financeAccountId'] ?? '').toString().trim();
      final conta = porId[contaId];
      // Compra no cartão é fatura — paga-se pela fatura, não aqui.
      if (conta != null && conta.isCreditCardProduct) continue;
      final ts = d['date'];
      if (ts is! Timestamp) continue;
      final dt = ts.toDate();
      final valor = ((d['amount'] as num?) ?? 0).toDouble().abs();
      if (valor <= 0) continue;
      out.add(_FixaItem(doc.id, d, DateTime(dt.year, dt.month, dt.day), valor,
          conta?.displayName ?? ''));
    }
    out.sort((a, b) => a.venc.compareTo(b.venc));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<FinanceAccount>>(
      stream: _contas,
      builder: (context, contasSnap) {
        final contas = contasSnap.data ?? const <FinanceAccount>[];
        return StreamBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
          stream: _docs,
          builder: (context, snap) {
            if (snap.hasData) _prazo?.cancel();
            if (!snap.hasData && (snap.hasError || _demorou)) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: FinanceLoadErrorBox(
                  error: snap.error,
                  message: snap.hasError
                      ? null
                      : 'As contas fixas estão demorando para carregar.',
                  onRetry: _tentarDeNovo,
                ),
              );
            }
            if (!snap.hasData) {
              return const SizedBox(
                height: 90,
                child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
              );
            }
            return _painel(context, _itens(snap.data!, contas), contas);
          },
        );
      },
    );
  }

  Widget _painel(
    BuildContext context,
    List<_FixaItem> itens,
    List<FinanceAccount> contas,
  ) {
    final inicioMes = DateTime(_hoje.year, _hoje.month, 1);
    final limite7 = _hoje.add(const Duration(days: 7));
    final abertos = itens.where((i) => !i.pago).toList();
    final vencidas = abertos.where((i) => i.venc.isBefore(_hoje)).toList();
    final proximas =
        abertos.where((i) => !i.venc.isBefore(_hoje) && !i.venc.isAfter(limite7)).toList();
    final depois =
        abertos.where((i) => i.venc.isAfter(limite7) && !i.venc.isAfter(_fimMes)).toList();
    final pagas = itens
        .where((i) => i.pago && !i.venc.isBefore(inicioMes) && !i.venc.isAfter(_fimMes))
        .toList()
      ..sort((a, b) => b.venc.compareTo(a.venc));

    double soma(List<_FixaItem> l) => l.fold(0.0, (a, i) => a + i.valor);
    final aPagar = [...vencidas, ...proximas, ...depois];
    final ultimoDia = aPagar.isEmpty
        ? _fimMes
        : aPagar.map((i) => i.venc).reduce((a, b) => a.isAfter(b) ? a : b);
    final ate = ultimoDia.isAfter(_fimMes) ? ultimoDia : _fimMes;

    final verbo = widget.receita ? 'a receber' : 'a pagar';
    final titulo = widget.receita ? 'O que tenho para receber' : 'O que tenho que pagar';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cor.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(color: _cor.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [_cor, _cor.withValues(alpha: 0.7)]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.receita ? Icons.savings_rounded : Icons.event_note_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(titulo,
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w900, color: context.appTextPrimary)),
                    Text('Fixas de ${_meses[_hoje.month - 1]}',
                        style: TextStyle(fontSize: 12, color: context.appTextSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _faixaResumo(
            context,
            icone: aPagar.isEmpty ? Icons.check_circle_rounded : Icons.schedule_rounded,
            cor: aPagar.isEmpty ? _kVerde : _kAzul,
            texto: aPagar.isEmpty
                ? (widget.receita
                    ? 'Tudo recebido neste mês'
                    : 'Tudo pago neste mês')
                : 'Você tem ${aPagar.length} ${aPagar.length == 1 ? 'conta' : 'contas'} '
                    '$verbo até ${_ddmm(ate)} · ${CurrencyFormats.formatBRL(soma(aPagar))}',
          ),
          if (vencidas.isNotEmpty) ...[
            const SizedBox(height: 6),
            _faixaResumo(
              context,
              icone: Icons.warning_amber_rounded,
              cor: _kVermelho,
              texto: '${vencidas.length} ${widget.receita ? (vencidas.length == 1 ? 'atrasada' : 'atrasadas') : (vencidas.length == 1 ? 'vencida' : 'vencidas')}'
                  ' · ${CurrencyFormats.formatBRL(soma(vencidas))}',
            ),
          ],
          if (vencidas.isNotEmpty)
            _secao(context, widget.receita ? 'Atrasadas' : 'Vencidas', _kVermelho, vencidas, contas),
          if (proximas.isNotEmpty)
            _secao(context, widget.receita ? 'Entram hoje e nos próximos 7 dias' : 'Vencem hoje e nos próximos 7 dias',
                _kLaranja, proximas, contas),
          if (depois.isNotEmpty)
            _secao(context, 'Ainda este mês', _kAzul, depois, contas),
          if (pagas.isNotEmpty) ...[
            _cabecalho(context, widget.receita ? 'Recebidas' : 'Pagas', _kVerde, pagas.length,
                soma(pagas),
                acao: TextButton(
                  onPressed: () => setState(() => _verPagas = !_verPagas),
                  child: Text(_verPagas ? 'Esconder' : 'Ver'),
                )),
            if (_verPagas)
              for (final i in pagas) _linhaPaga(context, i),
          ],
          if (itens.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Nenhuma fixa com lançamento neste mês.',
                style: TextStyle(fontSize: 13, color: context.appTextSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _faixaResumo(BuildContext context,
      {required IconData icone, required Color cor, required String texto}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cor.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          Icon(icone, size: 18, color: cor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(texto,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cor)),
          ),
        ],
      ),
    );
  }

  Widget _cabecalho(BuildContext context, String titulo, Color cor, int n, double total,
      {Widget? acao}) {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 4),
      child: Row(
        children: [
          Container(
              width: 10, height: 10, decoration: BoxDecoration(color: cor, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$titulo ($n)',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w900, color: cor)),
          ),
          Text(CurrencyFormats.formatBRL(total),
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: cor)),
          if (acao != null) acao,
        ],
      ),
    );
  }

  Widget _secao(BuildContext context, String titulo, Color cor, List<_FixaItem> l,
      List<FinanceAccount> contas) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _cabecalho(context, titulo, cor, l.length, l.fold(0.0, (a, i) => a + i.valor)),
        for (final i in l) _linhaAberta(context, i, cor, contas),
      ],
    );
  }

  String _quando(_FixaItem i) {
    final dias = i.venc.difference(_hoje).inDays;
    final v = widget.receita ? 'Entra' : 'Vence';
    if (dias == 0) return '$v hoje';
    if (dias == 1) return '$v amanhã';
    if (dias > 1) return '$v ${_ddmm(i.venc)} · em $dias dias';
    final atras = -dias;
    return '${widget.receita ? 'Era' : 'Venceu'} ${_ddmm(i.venc)} · há $atras ${atras == 1 ? 'dia' : 'dias'}';
  }

  Widget _diaBolha(_FixaItem i, Color cor) => Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text('${i.venc.day}',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: cor)),
      );

  Widget _linhaAberta(BuildContext context, _FixaItem i, Color cor, List<FinanceAccount> contas) {
    final ocupado = _ocupados.contains(i.id);
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: cor.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cor.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          _diaBolha(i, cor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.descricao,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14, color: context.appTextPrimary)),
                Text(
                  [_quando(i), if (i.contaNome.isNotEmpty) i.contaNome].join(' · '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: context.appTextSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(CurrencyFormats.formatBRL(i.valor),
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: cor)),
              const SizedBox(height: 4),
              SizedBox(
                height: 30,
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: widget.receita ? _kVerde : cor,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                  ),
                  onPressed: ocupado ? null : () => _pagar(i, contas),
                  child: ocupado
                      ? const SizedBox(
                          width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(widget.receita ? 'Receber' : 'Pagar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _linhaPaga(BuildContext context, _FixaItem i) {
    final pagoEm = i.pagoEm;
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(10, 6, 2, 6),
      decoration: BoxDecoration(
        color: _kVerde.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _kVerde.withValues(alpha: 0.16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: _kVerde, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(i.descricao,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13.5, color: context.appTextPrimary)),
                Text(
                  [
                    if (pagoEm != null)
                      '${widget.receita ? 'Recebido' : 'Pago'} em ${_ddmm(pagoEm)}'
                    else
                      'Venc. ${_ddmm(i.venc)}',
                    if (i.contaNome.isNotEmpty) i.contaNome,
                  ].join(' · '),
                  style: TextStyle(fontSize: 11.5, color: context.appTextSecondary),
                ),
              ],
            ),
          ),
          Text(CurrencyFormats.formatBRL(i.valor),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5, color: _kVerde)),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  void _snack(String msg, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      behavior: SnackBarBehavior.floating,
      backgroundColor: erro ? _kVermelho : null,
    ));
  }

  Future<void> _pagar(_FixaItem i, List<FinanceAccount> contas) async {
    // O mesmo «Confirmar pagamento» de sempre (entra no saldo).
    final contaId = (i.d['financeAccountId'] ?? '').toString().trim();
    final r = await showFinanceConfirmPaymentSheet(
      context: context,
      isIncome: widget.receita,
      financeAccounts: contas,
      initialFinanceAccountId: contaId.isEmpty ? null : contaId,
      orphanAccountId: contaId,
      amountPreview: i.valor,
      categoryPreview: (i.d['category'] ?? '').toString(),
      descriptionPreview: i.descricao,
    );
    if (r == null || !mounted) return;
    setState(() => _ocupados.add(i.id));
    try {
      await commitFinanceConfirmPayment(
        txRef: FirebaseFirestore.instance
            .collection('users')
            .doc(firestoreUserDocIdForAppShell(widget.uid))
            .collection('transactions')
            .doc(i.id),
        uid: widget.uid,
        result: r,
      );
      FinanceTransactionsHub.notifyMutated(uid: widget.uid, effectiveDate: i.venc);
      _snack(widget.receita ? 'Recebimento confirmado.' : 'Pagamento confirmado.');
    } catch (e) {
      _snack('Erro ao confirmar: ${e.toString().split('\n').first}', erro: true);
    } finally {
      if (mounted) setState(() => _ocupados.remove(i.id));
    }
  }
}
