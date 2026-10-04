// Detalhe de uma aplicação: posição (bruto, IR, IOF, líquido se resgatar
// hoje), lotes, marcos de imposto, movimentos e ações.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../constants/currency_formats.dart';
import '../../theme/app_colors.dart';
import '../../theme/theme_context.dart';
import 'investimento_form_page.dart';
import 'investimentos_calculo.dart';
import 'investimentos_repo.dart';
import 'investimentos_ui_comum.dart';

class InvestimentoDetalhePage extends StatefulWidget {
  const InvestimentoDetalhePage({super.key, required this.uid, required this.uidDoc, required this.investimentoId});
  final String uid, uidDoc, investimentoId;

  @override
  State<InvestimentoDetalhePage> createState() => _InvestimentoDetalhePageState();
}

class _InvestimentoDetalhePageState extends State<InvestimentoDetalhePage> {
  final _repo = InvestimentosRepo.instance;

  // Assinado UMA vez (nunca `.snapshots()` dentro do build — Firestore Web).
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _doc =
      _repo.col(widget.uidDoc).doc(widget.investimentoId).snapshots();
  IndicesBcb? _idx;

  @override
  void initState() {
    super.initState();
    _repo.indices().then((i) {
      if (mounted) setState(() => _idx = i);
    });
  }

  void _msg(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _movimento(Investimento inv, {required bool resgate}) async {
    final r = await dialogoMovimento(context, uid: widget.uid, inv: inv, resgate: resgate, idx: _idx);
    if (r == null) return;
    try {
      if (resgate) {
        final split = simularResgate(inv, _idx, r.data, r.valor);
        final g = await _repo.resgatar(widget.uidDoc, inv, valor: r.valor, data: r.data, conta: r.conta, split: split);
        _msg(g.rendimento > 0
            ? 'Resgate registrado. Rendimento de ${brl(g.rendimento)} lançado como receita.'
            : 'Resgate registrado.');
      } else {
        await _repo.aplicar(widget.uidDoc, inv, valor: r.valor, data: r.data, conta: r.conta);
        _msg('Aplicação registrada.');
      }
    } catch (e) {
      _msg('Não foi possível gravar: ${e.toString().split('\n').first}');
    }
  }

  Future<void> _valorManual(Investimento inv) async {
    final ctrl = TextEditingController(text: inv.valorAtual > 0 ? CurrencyFormats.formatBRLInput(inv.valorAtual) : '');
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Valor atual'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: CurrencyFormats.brlInputFormatters,
          decoration: const InputDecoration(prefixText: 'R\$ ', helperText: 'O valor que aparece hoje no banco/corretora.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, CurrencyFormats.parseBRLInput(ctrl.text)), child: const Text('Salvar')),
        ],
      ),
    );
    ctrl.dispose();
    if (v == null) return;
    await _repo.atualizarValorManual(widget.uidDoc, inv, v);
  }

  Future<void> _excluir(Investimento inv) async {
    var apagar = true;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Excluir aplicação?'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('«${inv.nomeExibicao}» sai da carteira.'),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: apagar,
              onChanged: (v) => setS(() => apagar = v ?? true),
              title: const Text('Apagar também os lançamentos de aplicação/resgate do Financeiro'),
              subtitle: const Text('O saldo da conta volta a ser o de antes.'),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    await _repo.excluir(widget.uidDoc, inv, apagarLancamentos: apagar);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _excluirMovimento(Investimento inv, MovimentoInvestimento m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(m.resgate ? 'Apagar resgate?' : 'Apagar aplicação?'),
        content: Text('${brl(m.valor)} em ${dataBr(m.data)}. Os lançamentos ligados no Financeiro também saem.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Apagar')),
        ],
      ),
    );
    if (ok == true) await _repo.excluirMovimento(widget.uidDoc, inv, m);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _doc,
      builder: (context, snap) {
        if (snap.hasError) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Não foi possível abrir a aplicação.')));
        }
        final d = snap.data;
        if (d == null || _idx == null) {
          return Scaffold(appBar: AppBar(), body: const Center(child: CircularProgressIndicator()));
        }
        if (!d.exists) {
          return Scaffold(appBar: AppBar(), body: const Center(child: Text('Aplicação excluída.')));
        }
        final inv = Investimento.fromMap(d.id, d.data() ?? {});
        final hoje = hojeBrasilia();
        final r = resumo(inv, _idx, hoje);
        final p = r.posicao;
        final cor = kCorPorTipo[inv.tipo] ?? AppColors.primary;
        final movs = movimentosOrdenados(inv).reversed.toList();
        return Scaffold(
          appBar: AppBar(
            title: Text(inv.nomeExibicao, overflow: TextOverflow.ellipsis),
            actions: [
              IconButton(
                tooltip: 'Editar',
                icon: const Icon(Icons.edit_rounded),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => InvestimentoFormPage(uid: widget.uid, uidDoc: widget.uidDoc, inicial: inv))),
              ),
              IconButton(tooltip: 'Excluir', icon: const Icon(Icons.delete_outline_rounded), onPressed: () => _excluir(inv)),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: context.appPanelDecoration(radius: 18, borderAccent: cor),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      CircleAvatar(backgroundColor: cor.withValues(alpha: 0.15), child: Icon(iconeDoTipo(inv.tipo), color: cor)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          [infoTipo(inv.tipo).rotulo, rotuloTaxa(inv), if (inv.banco.isNotEmpty) inv.banco].join(' · '),
                          style: TextStyle(color: context.appTextSecondary),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Text(brl(p.bruto), style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: context.appDeepTitle)),
                    Text('valor bruto hoje', style: TextStyle(color: context.appTextMuted, fontSize: 12)),
                    const Divider(height: 24),
                    LinhaValor('Aplicado (ainda investido)', brl(p.investido)),
                    LinhaValor('Rendimento bruto', brl(p.rendimento), cor: corDoValor(context, p.rendimento)),
                    if (!infoTipo(inv.tipo).semImposto) ...[
                      LinhaValor('IOF se resgatar hoje', brl(p.iof)),
                      LinhaValor(inv.isentoIR ? 'IR (isento)' : 'IR se resgatar hoje', brl(p.ir)),
                    ] else
                      const LinhaValor('Impostos', 'não estimados'),
                    LinhaValor('Líquido se resgatar hoje', brl(p.liquido), negrito: true),
                    const Divider(height: 24),
                    LinhaValor('Rendeu no último dia útil', r.rendDia == null ? '—' : brl(r.rendDia), cor: corDoValor(context, r.rendDia)),
                    LinhaValor('Rendeu no mês', r.rendMes == null ? '—' : brl(r.rendMes), cor: corDoValor(context, r.rendMes)),
                    LinhaValor('Rendimento acumulado', brl(r.rendAcumulado), cor: corDoValor(context, r.rendAcumulado)),
                    if (inv.vencimento.isNotEmpty) LinhaValor('Vencimento', dataBr(inv.vencimento)),
                    if (inv.manual && inv.valorAtualEm.isNotEmpty) LinhaValor('Valor informado em', dataBr(inv.valorAtualEm)),
                    AvisoEstimativa(ultimaTaxa: _idx!.ultimaAtualizacao),
                  ]),
                ),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(
                    onPressed: () => _movimento(inv, resgate: false),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Aplicar mais'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: p.investido > 0 ? () => _movimento(inv, resgate: true) : null,
                    icon: const Icon(Icons.south_west_rounded),
                    label: const Text('Resgatar'),
                  ),
                  if (inv.manual)
                    OutlinedButton.icon(
                      onPressed: () => _valorManual(inv),
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('Atualizar valor'),
                    ),
                ]),
                if (r.marcos.isNotEmpty) ...[
                  const SizedBox(height: 18),
                  Text('Próximos marcos de imposto', style: TextStyle(fontWeight: FontWeight.w800, color: context.appDeepTitle)),
                  const SizedBox(height: 6),
                  for (final m in r.marcos.take(6))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(m.tipo == 'iof_zero' ? Icons.money_off_rounded : Icons.trending_down_rounded,
                          color: AppColors.accent),
                      title: Text(m.tipo == 'iof_zero'
                          ? 'IOF zera em ${dataBr(m.data)}'
                          : 'IR cai para ${m.aliquota!.toStringAsFixed(1).replaceAll('.', ',')}% em ${dataBr(m.data)}'),
                    ),
                ],
                if (p.lotes.length > 1) ...[
                  const SizedBox(height: 12),
                  Text('Lotes (o resgate sai do mais antigo)',
                      style: TextStyle(fontWeight: FontWeight.w800, color: context.appDeepTitle)),
                  for (final l in p.lotes)
                    LinhaValor('${dataBr(l.data)} · ${l.dias} dias · IR ${irAliquota(l.dias).toStringAsFixed(1).replaceAll('.', ',')}%',
                        brl(l.bruto)),
                ],
                const SizedBox(height: 18),
                Text('Movimentos', style: TextStyle(fontWeight: FontWeight.w800, color: context.appDeepTitle)),
                for (final m in movs)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(m.resgate ? Icons.south_west_rounded : Icons.north_east_rounded,
                        color: m.resgate ? AppColors.financeReceita : AppColors.primary),
                    title: Text('${m.resgate ? 'Resgate' : 'Aplicação'} · ${brl(m.valor)}'),
                    subtitle: Text('${dataBr(m.data)}${m.transacoes.isEmpty ? ' · sem lançamento no Financeiro' : ''}'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => unawaited(_excluirMovimento(inv, m)),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
