// Carteira de Investimentos — painel (patrimônio, divisão por tipo e banco,
// evolução mês a mês × CDI × poupança, reserva de emergência) e lista.

import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../models/user_profile.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_context.dart';
import '../../utils/firestore_user_doc_id.dart';
import '../../utils/premium_upgrade.dart';
import '../../widgets/app_pie_chart.dart';
import 'investimento_detalhe_page.dart';
import 'investimento_form_page.dart';
import 'investimentos_calculo.dart';
import 'investimentos_repo.dart';
import 'investimentos_ui_comum.dart';

/// Totais da carteira (usado pelo painel e pelo card do Financeiro).
class TotaisCarteira {
  double bruto = 0, liquido = 0, investido = 0, mes = 0, dia = 0, acumulado = 0;
  final Map<String, double> porTipo = {};
  final Map<String, double> porBanco = {};
  final Map<String, ResumoInvestimento> porId = {};

  static TotaisCarteira de(List<Investimento> lista, IndicesBcb idx, String hoje) {
    final t = TotaisCarteira();
    for (final i in lista) {
      if (!i.ativo) continue;
      final r = resumo(i, idx, hoje);
      t.porId[i.id] = r;
      final p = r.posicao;
      if (p.bruto <= 0.004 && p.investido <= 0.004) continue;
      t.bruto += p.bruto;
      t.liquido += p.liquido;
      t.investido += p.investido;
      t.mes += r.rendMes ?? 0;
      t.dia += r.rendDia ?? 0;
      t.acumulado += r.rendAcumulado;
      t.porTipo[i.tipo] = (t.porTipo[i.tipo] ?? 0) + p.bruto;
      final banco = i.banco.trim().isEmpty ? 'Sem banco' : i.banco.trim();
      t.porBanco[banco] = (t.porBanco[banco] ?? 0) + p.bruto;
    }
    return t;
  }
}

class InvestimentosPage extends StatefulWidget {
  const InvestimentosPage({super.key, required this.uid, required this.profile});
  final String uid;
  final UserProfile profile;

  @override
  State<InvestimentosPage> createState() => _InvestimentosPageState();
}

class _InvestimentosPageState extends State<InvestimentosPage> {
  final _repo = InvestimentosRepo.instance;
  late final String _uidDoc = firestoreUserDocIdForAppShell(widget.uid);

  // Assinado UMA vez (Firestore Web — nunca `.snapshots()` dentro do build).
  late final Stream<List<Investimento>> _stream = _repo.stream(_uidDoc);
  late final Future<({double mediaMensal, double sugestao})> _reserva =
      _repo.sugestaoReservaEmergencia(_uidDoc).catchError((_) => (mediaMensal: 0.0, sugestao: 0.0));
  IndicesBcb? _idx;
  String _chaveEvolucao = '';
  List<({String mes, double carteira, double cdi, double poupanca})> _evolucao = const [];

  @override
  void initState() {
    super.initState();
    _repo.indices().then((i) {
      if (mounted) setState(() => _idx = i);
    });
  }

  bool get _podeEditar => widget.profile.hasActiveLicense;

  Future<void> _nova() async {
    if (!_podeEditar) {
      mostrarAvisoSeLicencaInativa(context, widget.profile);
      return;
    }
    await Navigator.of(context)
        .push(MaterialPageRoute<bool>(builder: (_) => InvestimentoFormPage(uid: widget.uid, uidDoc: _uidDoc)));
  }

  void _abrir(Investimento i) {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => InvestimentoDetalhePage(uid: widget.uid, uidDoc: _uidDoc, investimentoId: i.id)));
  }

  Future<void> _config() async {
    var v = await _repo.rendimentoComoReceita(_uidDoc);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: v,
                title: const Text('Rendimento vira receita ao resgatar'),
                subtitle: const Text(
                    'Ligado: no resgate, o que rendeu entra como receita em «Rendimentos». '
                    'Desligado: o resgate inteiro é só movimentação (fora das receitas).'),
                onChanged: (n) async {
                  setS(() => v = n);
                  await _repo.definirRendimentoComoReceita(_uidDoc, n);
                },
              ),
              const SizedBox(height: 6),
              Text(
                'Aplicar e resgatar nunca contam como despesa/receita: o dinheiro sai do saldo da conta e '
                'aparece como patrimônio investido.',
                style: TextStyle(fontSize: 12.5, color: ctx.appTextMuted),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  /// Bruto no fim de cada mês: carteira × mesmos movimentos no CDI 100% × poupança.
  void _calcularEvolucao(List<Investimento> lista, IndicesBcb idx, String hoje) {
    final chave = '$hoje|${lista.map((i) => '${i.id}:${i.movimentos.length}:${i.taxa}:${i.indexador}').join('|')}';
    if (chave == _chaveEvolucao) return;
    _chaveEvolucao = chave;
    final base = lista.where((i) => i.ativo && !i.manual).toList();
    if (base.isEmpty) {
      _evolucao = const [];
      return;
    }
    final soma = <String, List<double>>{};
    for (final i in base) {
      final a = evolucaoMensal(i, idx, hoje);
      final b = evolucaoMensal(comoSeFosse(i, 'cdi', 100), idx, hoje);
      final c = evolucaoMensal(comoSeFosse(i, 'poupanca', 0), idx, hoje);
      for (var k = 0; k < a.length; k++) {
        final s = soma.putIfAbsent(a[k].mes, () => [0, 0, 0]);
        s[0] += a[k].bruto;
        s[1] += b[k].bruto;
        s[2] += c[k].bruto;
      }
    }
    final meses = soma.keys.toList()..sort();
    _evolucao = [for (final m in meses) (mes: m, carteira: soma[m]![0], cdi: soma[m]![1], poupanca: soma[m]![2])];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Investimentos'),
        actions: [IconButton(tooltip: 'Configurar', icon: const Icon(Icons.tune_rounded), onPressed: _config)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _nova,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Nova aplicação'),
      ),
      body: SafeArea(
        child: StreamBuilder<List<Investimento>>(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasError) {
              return const Center(child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Não foi possível carregar a carteira. Saia e entre de novo se persistir.', textAlign: TextAlign.center),
              ));
            }
            final idx = _idx;
            if (!snap.hasData || idx == null) return const Center(child: CircularProgressIndicator());
            final lista = snap.data!.where((i) => i.ativo).toList();
            final hoje = hojeBrasilia();
            final t = TotaisCarteira.de(lista, idx, hoje);
            _calcularEvolucao(lista, idx, hoje);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              children: [
                _cabecalho(t, idx),
                const SizedBox(height: 12),
                _cardReserva(lista, idx, hoje),
                if (lista.isEmpty) _vazio(),
                if (t.porTipo.length > 1 || t.porBanco.length > 1) ...[
                  const SizedBox(height: 12),
                  _divisoes(t),
                ],
                if (_evolucao.length > 1 && _evolucao.last.carteira > 0) ...[
                  const SizedBox(height: 12),
                  _cardEvolucao(),
                ],
                const SizedBox(height: 16),
                if (lista.isNotEmpty)
                  Text('Aplicações', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: context.appDeepTitle)),
                const SizedBox(height: 6),
                for (final i in lista) _cardAplicacao(i, t.porId[i.id]),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _cabecalho(TotaisCarteira t, IndicesBcb idx) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(colors: AppColors.logoGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Patrimônio investido', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(brl(t.bruto), style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.w900)),
        ),
        Text('Líquido se resgatar hoje: ${brl(t.liquido)}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Wrap(spacing: 18, runSpacing: 8, children: [
          _chip('Aplicado', brl(t.investido)),
          _chip('Rendeu no mês', brl(t.mes)),
          _chip('Último dia útil', brl(t.dia)),
          _chip('Acumulado', brl(t.acumulado)),
        ]),
        const SizedBox(height: 8),
        Text('$kAvisoEstimativa${idx.ultimaAtualizacao.isEmpty ? '' : ' Taxas até ${dataBr(idx.ultimaAtualizacao)}.'}',
            style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
      ]),
    );
  }

  Widget _chip(String r, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(r, style: const TextStyle(color: Colors.white70, fontSize: 11.5)),
        Text(v, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
      ]);

  Widget _vazio() => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(20),
        decoration: context.appPanelDecoration(radius: 18),
        child: Column(children: [
          Icon(Icons.savings_rounded, size: 48, color: AppColors.primary.withValues(alpha: 0.5)),
          const SizedBox(height: 8),
          Text('Nenhuma aplicação ainda', style: TextStyle(fontWeight: FontWeight.w800, color: context.appDeepTitle)),
          const SizedBox(height: 6),
          Text(
            'CDB, LCI/LCA, Tesouro, poupança, caixinhas, previdência, fundos, ações e FIIs. '
            'O rendimento é calculado com as taxas oficiais do Banco Central.',
            textAlign: TextAlign.center,
            style: TextStyle(color: context.appTextSecondary),
          ),
        ]),
      );

  Widget _cardReserva(List<Investimento> lista, IndicesBcb idx, String hoje) {
    return FutureBuilder<({double mediaMensal, double sugestao})>(
      future: _reserva,
      builder: (context, s) {
        final r = s.data;
        if (r == null || r.sugestao <= 0) return const SizedBox.shrink();
        final liquidez = lista
            .where((i) => i.liquidezDiaria)
            .fold(0.0, (a, i) => a + posicao(i, idx, hoje).liquido);
        final pct = (liquidez / r.sugestao).clamp(0.0, 1.0);
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: context.appPanelDecoration(radius: 16, borderAccent: AppColors.accent),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.health_and_safety_rounded, color: AppColors.accent),
              const SizedBox(width: 8),
              Expanded(child: Text('Reserva de emergência', style: TextStyle(fontWeight: FontWeight.w800, color: context.appDeepTitle))),
              Text('${(pct * 100).round()}%', style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.accent)),
            ]),
            const SizedBox(height: 6),
            Text(
              'Sugestão: ${brl(r.sugestao)} (6 × a média de despesas dos últimos 3 meses, ${brl(r.mediaMensal)}/mês). '
              'Com liquidez diária você tem ${brl(liquidez)}.',
              style: TextStyle(fontSize: 12.5, color: context.appTextSecondary),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: pct, minHeight: 8, color: AppColors.accent),
            ),
          ]),
        );
      },
    );
  }

  Widget _divisoes(TotaisCarteira t) {
    final tipos = t.porTipo.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final bancos = t.porBanco.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final pTipo = AppPieChart(
      title: 'Por tipo',
      segments: [
        for (final e in tipos) (label: infoTipo(e.key).rotulo, value: e.value, color: kCorPorTipo[e.key] ?? AppColors.primary),
      ],
    );
    final pBanco = AppPieChart(
      title: 'Por banco',
      segments: [
        for (var k = 0; k < bancos.length; k++)
          (label: bancos[k].key, value: bancos[k].value, color: kCoresBancos[k % kCoresBancos.length]),
      ],
    );
    return LayoutBuilder(builder: (context, c) {
      if (c.maxWidth >= 640) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: pTipo),
          const SizedBox(width: 12),
          Expanded(child: pBanco),
        ]);
      }
      return Column(children: [pTipo, const SizedBox(height: 12), pBanco]);
    });
  }

  Widget _cardEvolucao() {
    final ev = _evolucao;
    final ult = ev.last;
    String mesCurto(String m) => '${m.substring(5)}/${m.substring(2, 4)}';
    LineChartBarData serie(List<double> v, Color cor, {bool tracejado = false}) => LineChartBarData(
          spots: [for (var k = 0; k < v.length; k++) FlSpot(k.toDouble(), v[k])],
          isCurved: true,
          color: cor,
          barWidth: tracejado ? 2 : 3,
          dashArray: tracejado ? [6, 4] : null,
          dotData: const FlDotData(show: false),
        );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 14, 16, 12),
      decoration: context.appPanelDecoration(radius: 18),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4),
          child: Text('Evolução mês a mês', style: TextStyle(fontWeight: FontWeight.w800, color: context.appDeepTitle)),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 200,
          child: LineChart(LineChartData(
            gridData: const FlGridData(show: true, drawVerticalLine: false),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  interval: 2,
                  getTitlesWidget: (v, meta) {
                    final k = v.round();
                    if (k < 0 || k >= ev.length) return const SizedBox.shrink();
                    return Text(mesCurto(ev[k].mes), style: TextStyle(fontSize: 10, color: context.appTextMuted));
                  },
                ),
              ),
            ),
            lineBarsData: [
              serie([for (final e in ev) e.carteira], AppColors.primary),
              serie([for (final e in ev) e.cdi], AppColors.accent, tracejado: true),
              serie([for (final e in ev) e.poupanca], AppColors.amber, tracejado: true),
            ],
          )),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 14, runSpacing: 4, children: [
          _legenda(AppColors.primary, 'Sua carteira ${brl(ult.carteira)}'),
          _legenda(AppColors.accent, 'No CDI 100% ${brl(ult.cdi)}'),
          _legenda(AppColors.amber, 'Na poupança ${brl(ult.poupanca)}'),
        ]),
        const SizedBox(height: 4),
        Text('Mesmas aplicações e resgates simulados no CDI e na poupança (valores brutos). '
            'Ações/FIIs/fundos com valor informado à mão ficam de fora.',
            style: TextStyle(fontSize: 11.5, color: context.appTextMuted)),
      ]),
    );
  }

  Widget _legenda(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text(t, style: TextStyle(fontSize: 12, color: context.appTextSecondary)),
      ]);

  Widget _cardAplicacao(Investimento i, ResumoInvestimento? r) {
    final cor = kCorPorTipo[i.tipo] ?? AppColors.primary;
    final p = r?.posicao;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _abrir(i),
          child: Ink(
            padding: const EdgeInsets.all(14),
            decoration: context.appPanelDecoration(radius: 16),
            child: Row(children: [
              CircleAvatar(backgroundColor: cor.withValues(alpha: 0.15), child: Icon(iconeDoTipo(i.tipo), color: cor)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.nomeExibicao, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, color: context.appDeepTitle)),
                  Text(
                    [rotuloTaxa(i), if (i.vencimento.isNotEmpty) 'vence ${dataBr(i.vencimento)}', if (i.liquidezDiaria) 'liquidez diária']
                        .join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: context.appTextMuted),
                  ),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(brl(p?.bruto ?? 0), style: TextStyle(fontWeight: FontWeight.w800, color: context.appTextPrimary)),
                if (r?.rendMes != null)
                  Text('mês ${brl(r!.rendMes)}', style: TextStyle(fontSize: 12, color: corDoValor(context, r.rendMes))),
              ]),
            ]),
          ),
        ),
      ),
    );
  }
}
