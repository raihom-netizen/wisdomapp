// Cadastro / edição de uma aplicação da carteira.

import 'package:flutter/material.dart';

import '../../constants/currency_formats.dart';
import '../../models/finance_account.dart';
import '../../theme/theme_context.dart';
import 'investimentos_calculo.dart';
import 'investimentos_repo.dart';
import 'investimentos_ui_comum.dart';

class InvestimentoFormPage extends StatefulWidget {
  const InvestimentoFormPage({super.key, required this.uid, required this.uidDoc, this.inicial});

  /// uid do shell (contas) e id do doc do usuário (titular quando sub-login).
  final String uid, uidDoc;
  final Investimento? inicial;

  @override
  State<InvestimentoFormPage> createState() => _InvestimentoFormPageState();
}

class _InvestimentoFormPageState extends State<InvestimentoFormPage> {
  late String _tipo = widget.inicial?.tipo ?? 'cdb';
  late String _indexador = widget.inicial?.indexador ?? 'cdi';
  late final _nome = TextEditingController(text: widget.inicial?.nome ?? '');
  late final _banco = TextEditingController(text: widget.inicial?.banco ?? '');
  late final _taxa = TextEditingController(
      text: widget.inicial == null ? '100' : widget.inicial!.taxa.toString().replaceAll('.', ',').replaceAll(RegExp(r',0$'), ''));
  final _valor = TextEditingController();
  late final _valorAtual = TextEditingController(
      text: (widget.inicial?.valorAtual ?? 0) > 0 ? CurrencyFormats.formatBRLInput(widget.inicial!.valorAtual) : '');
  late String _vencimento = widget.inicial?.vencimento ?? '';
  String _dataInicial = hojeBrasilia();
  late bool _liquidez = widget.inicial?.liquidezDiaria ?? false;
  late bool _avisos = widget.inicial?.avisos ?? true;
  late String _metaId = widget.inicial?.metaId ?? '';
  String _contaId = '';
  List<FinanceAccount> _contas = const [];
  Map<String, String> _metas = const {};
  bool _salvando = false;

  bool get _editando => widget.inicial != null && widget.inicial!.id.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _contaId = widget.inicial?.contaId ?? '';
    contasParaInvestir(widget.uid).then((l) {
      if (!mounted) return;
      setState(() {
        _contas = l;
        if (_contaId.isEmpty && l.isNotEmpty && !_editando) _contaId = l.first.id;
      });
    });
    InvestimentosRepo.instance.metasAtivas(widget.uidDoc).then((m) {
      if (mounted) setState(() => _metas = m);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _nome.dispose();
    _banco.dispose();
    _taxa.dispose();
    _valor.dispose();
    _valorAtual.dispose();
    super.dispose();
  }

  void _trocarTipo(String t) {
    setState(() {
      _tipo = t;
      _indexador = infoTipo(t).indexador;
      if (_indexador == 'cdi' && lerNumero(_taxa.text) == 0) _taxa.text = '100';
      if (t == 'caixinha' || t == 'poupanca' || t == 'tesouro_selic') _liquidez = true;
    });
  }

  String get _rotuloTaxa {
    switch (_indexador) {
      case 'cdi':
        return '% do CDI (ex.: 110)';
      case 'selic':
        return 'Selic + (taxa a.a., ex.: 0,05)';
      case 'pre':
        return 'Taxa prefixada ao ano';
      case 'ipca':
        return 'IPCA + (taxa real ao ano)';
      default:
        return 'Taxa';
    }
  }

  Future<void> _salvar() async {
    final valorInicial = CurrencyFormats.parseBRLInput(_valor.text) ?? 0;
    final conta = _contas.where((c) => c.id == _contaId).firstOrNull;
    final inv = (widget.inicial ?? const Investimento()).copyWith(
      nome: _nome.text.trim().isEmpty
          ? [infoTipo(_tipo).rotulo, if (_banco.text.trim().isNotEmpty) _banco.text.trim()].join(' · ')
          : _nome.text.trim(),
      tipo: _tipo,
      indexador: _indexador,
      taxa: _indexador == 'poupanca' || _indexador == 'manual' ? 0 : lerNumero(_taxa.text),
      banco: _banco.text.trim(),
      contaId: conta?.id ?? '',
      contaNome: conta?.displayName ?? '',
      vencimento: _vencimento,
      liquidezDiaria: _liquidez,
      avisos: _avisos,
      metaId: _metaId,
      valorAtual: _indexador == 'manual' ? (CurrencyFormats.parseBRLInput(_valorAtual.text) ?? 0) : 0,
      valorAtualEm: _indexador == 'manual' ? hojeBrasilia() : '',
    );
    if (!_editando && valorInicial <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Informe o valor aplicado.')));
      return;
    }
    setState(() => _salvando = true);
    try {
      await InvestimentosRepo.instance.salvarCadastro(
        widget.uidDoc,
        inv,
        valorInicial: _editando ? 0 : valorInicial,
        dataInicial: _dataInicial,
        conta: _editando ? null : conta,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Não foi possível salvar: ${e.toString().split('\n').first}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final manual = _indexador == 'manual';
    return Scaffold(
      appBar: AppBar(title: Text(_editando ? 'Editar aplicação' : 'Nova aplicação')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _tipo,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Tipo'),
              items: [for (final t in kTiposInvestimento) DropdownMenuItem(value: t.id, child: Text(t.rotulo))],
              onChanged: (v) => v == null ? null : _trocarTipo(v),
            ),
            const SizedBox(height: 10),
            if (!manual && _tipo != 'poupanca')
              DropdownButtonFormField<String>(
                initialValue: _indexador,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Como rende'),
                items: const [
                  DropdownMenuItem(value: 'cdi', child: Text('% do CDI (pós-fixado)')),
                  DropdownMenuItem(value: 'pre', child: Text('Prefixado (% ao ano)')),
                  DropdownMenuItem(value: 'ipca', child: Text('IPCA + taxa')),
                  DropdownMenuItem(value: 'selic', child: Text('Selic')),
                ],
                onChanged: (v) => setState(() => _indexador = v ?? _indexador),
              ),
            if (!manual && _tipo != 'poupanca') ...[
              const SizedBox(height: 10),
              CampoTaxa(controller: _taxa, rotulo: _rotuloTaxa),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: _banco,
              decoration: const InputDecoration(labelText: 'Banco / corretora', hintText: 'Nubank, Inter, XP…'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nome,
              decoration: const InputDecoration(labelText: 'Nome (opcional)', hintText: 'Ex.: Reserva de emergência'),
            ),
            const SizedBox(height: 10),
            if (!_editando) ...[
              TextField(
                controller: _valor,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: CurrencyFormats.brlInputFormatters,
                decoration: const InputDecoration(labelText: 'Valor aplicado', prefixText: 'R\$ '),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text('Data da aplicação: ${dataBr(_dataInicial)}'),
                onPressed: () async {
                  final r = await escolherData(context, _dataInicial);
                  if (r != null) setState(() => _dataInicial = r);
                },
              ),
              const SizedBox(height: 10),
            ],
            if (manual) ...[
              TextField(
                controller: _valorAtual,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: CurrencyFormats.brlInputFormatters,
                decoration: const InputDecoration(
                  labelText: 'Valor atual (opcional)',
                  prefixText: 'R\$ ',
                  helperText: 'Ações, FIIs, fundos e previdência: atualize à mão quando quiser.',
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_contas.isNotEmpty)
              DropdownButtonFormField<String>(
                initialValue: _contas.any((c) => c.id == _contaId) ? _contaId : '',
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _editando ? 'Conta de origem (padrão)' : 'Sai da conta',
                  helperText: _editando ? null : 'O dinheiro sai do saldo da conta — não conta como despesa.',
                ),
                items: [
                  for (final c in _contas) DropdownMenuItem(value: c.id, child: Text(c.displayName, overflow: TextOverflow.ellipsis)),
                  const DropdownMenuItem(value: '', child: Text('Sem conta (só a carteira)')),
                ],
                onChanged: (v) => setState(() => _contaId = v ?? ''),
              ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              icon: const Icon(Icons.event_available_rounded, size: 18),
              label: Text(_vencimento.isEmpty ? 'Vencimento (opcional)' : 'Vence em ${dataBr(_vencimento)}'),
              onPressed: () async {
                final r = await escolherData(context, _vencimento.isEmpty ? hojeBrasilia() : _vencimento);
                if (r != null) setState(() => _vencimento = r);
              },
            ),
            if (_vencimento.isNotEmpty)
              TextButton(onPressed: () => setState(() => _vencimento = ''), child: const Text('Sem vencimento')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _liquidez,
              title: const Text('Liquidez diária'),
              onChanged: (v) => setState(() => _liquidez = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _avisos,
              title: const Text('Avisos'),
              subtitle: Text('Vencimento, IOF zerado, IR menor e «rendeu menos que a poupança»',
                  style: TextStyle(color: context.appTextMuted, fontSize: 12)),
              onChanged: (v) => setState(() => _avisos = v),
            ),
            if (_metas.isNotEmpty) ...[
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _metas.containsKey(_metaId) ? _metaId : '',
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Conta para a meta',
                  helperText: 'O valor líquido da aplicação entra no progresso da meta.',
                ),
                items: [
                  const DropdownMenuItem(value: '', child: Text('Nenhuma meta')),
                  for (final e in _metas.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _metaId = v ?? ''),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: _salvando
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.check_rounded),
              label: Text(_editando ? 'Salvar' : 'Registrar aplicação'),
            ),
          ],
        ),
      ),
    );
  }
}
