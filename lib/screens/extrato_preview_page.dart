import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../theme/theme_context.dart';
import '../utils/extrato_import.dart';

/// Limite da descrição — o mesmo da ficha do lançamento no Controle Total.
const int kExtratoDescricaoMax = 500;

/// Pré-visualização do arquivo importado, em tela cheia.
///
/// A regra desta tela é uma só: **nada é gravado antes de o usuário tocar em
/// Confirmar.** Ela existe para ele conferir 60 lançamentos em dez segundos —
/// por isso o total e o rateio por categoria vêm ANTES da lista, e cada linha
/// é um toque para desmarcar.
///
/// O que já vem decidido (e por quê):
///   - o que já existe no app nasce **desmarcado e riscado**, não escondido:
///     esconder faria o arquivo parecer incompleto;
///   - «pagamento da fatura» também nasce desmarcado — pagar o cartão não é
///     receita, é dinheiro saindo da conta para o cartão;
///   - a categoria já vem preenchida, e o chip abre a troca em um toque.
class ExtratoPreviewPage extends StatefulWidget {
  const ExtratoPreviewPage({
    super.key,
    required this.lote,
    required this.categoriasDespesa,
    required this.categoriasReceita,
    required this.onConfirmar,
    this.contaNome = '',
    this.cartao = false,
  });

  final ExtratoLote lote;

  /// Categorias que o usuário tem hoje (o chip só oferece o que existe).
  final List<String> categoriasDespesa;
  final List<String> categoriasReceita;

  /// Grava os marcados. A tela fecha sozinha quando isto termina sem erro.
  /// `ehFatura` é o tipo COMO ESTÁ na tela — o usuário pode ter trocado.
  final Future<void> Function(List<ExtratoItem> marcados, bool ehFatura) onConfirmar;

  /// Onde o dinheiro vai cair, só para o usuário conferir.
  final String contaNome;

  /// A conta de destino tem cartão (cartão ou conta + cartão): a fatura
  /// entra como compra pendente, e a tela avisa antes de gravar.
  final bool cartao;

  @override
  State<ExtratoPreviewPage> createState() => _ExtratoPreviewPageState();
}

class _ExtratoPreviewPageState extends State<ExtratoPreviewPage> {
  late ExtratoLote _lote = widget.lote;
  bool _gravando = false;

  static const _vermelho = Color(0xFFDC2626);
  static const _verde = Color(0xFF16A34A);

  /// Paleta do rateio — seis tons que se distinguem no claro e no escuro.
  static const _paleta = <Color>[
    Color(0xFF6366F1),
    Color(0xFF0D9488),
    Color(0xFFF59E0B),
    Color(0xFFEC4899),
    Color(0xFF3B82F6),
    Color(0xFF8B5CF6),
  ];

  List<ExtratoItem> get _marcados =>
      _lote.itens.where((i) => i.marcado).toList();

  String _money(double v) {
    final s = v.toStringAsFixed(2).replaceAll('.', ',');
    final partes = s.split(',');
    final inteiro = partes[0].replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'),
      (m) => '${m[1]}.',
    );
    return 'R\$ $inteiro,${partes[1]}';
  }

  String _ddmm(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    final r = extratoResumir(_marcados);
    final total = _lote.itens.length;

    return Scaffold(
      backgroundColor: ctx.appScaffold,
      appBar: AppBar(
        backgroundColor: _lote.fatura ? const Color(0xFF7C3AED) : const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Icon(
              _lote.fatura ? Icons.credit_card_rounded : Icons.receipt_long_rounded,
              size: 20,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                _lote.fatura ? 'Fatura lida' : 'Extrato lido',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
              ),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: Colors.white),
            onPressed: _gravando ? null : _trocarTipo,
            icon: Icon(
              _lote.fatura ? Icons.account_balance_rounded : Icons.credit_card_rounded,
              size: 18,
            ),
            label: Text(_lote.fatura ? 'É extrato' : 'É fatura'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              children: [
                _cabecalho(ctx, r, total),
                const SizedBox(height: 14),
                if (_marcados.any((i) => !i.credito)) ...[
                  _rateio(ctx, r),
                  const SizedBox(height: 14),
                ],
                _avisos(ctx),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Lançamentos ($total)',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: ctx.appTextPrimary,
                      ),
                    ),
                    TextButton(
                      onPressed: _gravando ? null : _alternarTodos,
                      child: Text(
                        _marcados.length == total ? 'Desmarcar todos' : 'Marcar todos',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ..._lote.itens.asMap().entries.map((e) => _linha(ctx, e.key, e.value)),
              ],
            ),
          ),
          _rodape(ctx),
        ],
      ),
    );
  }

  // ─────────────────────────── cabeçalho ───────────────────────────

  Widget _cabecalho(BuildContext ctx, ExtratoResumo r, int total) {
    final periodo = r.de != null && r.ate != null
        ? '${_ddmm(r.de!)} a ${_ddmm(r.ate!)}'
        : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _lote.fatura
              ? const [Color(0xFF7C3AED), Color(0xFFA78BFA)]
              : const [Color(0xFF0F766E), Color(0xFF14B8A6)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _lote.fatura ? Icons.credit_card_rounded : Icons.account_balance_rounded,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  [
                    if (_lote.nomeArquivo.isNotEmpty) _lote.nomeArquivo,
                    if (_lote.banco.isNotEmpty) _lote.banco,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            _money(r.totalDespesas),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.8,
            ),
          ),
          Text(
            '${r.despesas} despesa(s) marcada(s)'
            '${periodo.isEmpty ? '' : ' · $periodo'}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 12.5,
            ),
          ),
          if (r.totalReceitas > 0) ...[
            const SizedBox(height: 8),
            Text(
              '+ ${_money(r.totalReceitas)} em ${r.receitas} receita(s)',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.95),
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (widget.contaNome.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                widget.cartao && _lote.fatura
                    ? '💳 ${widget.contaNome} · fatura: compras pendentes até pagar'
                    : '🏦 ${widget.contaNome}',
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────── rateio ───────────────────────────

  Widget _rateio(BuildContext ctx, ExtratoResumo r) {
    final grupos = extratoPorCategoria(_marcados.where((i) => !i.credito).toList());
    final total = r.totalDespesas;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: ctx.appSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ctx.appBorderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Por categoria',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: ctx.appTextPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...grupos.take(8).toList().asMap().entries.map((e) {
            final g = e.value;
            final cor = _paleta[e.key % _paleta.length];
            final pct = total > 0 ? (g.total / total) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(color: cor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          g.categoria,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: ctx.appTextPrimary,
                          ),
                        ),
                      ),
                      Text(
                        '${_money(g.total)}  ',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: ctx.appTextPrimary,
                        ),
                      ),
                      Text(
                        '${(pct * 100).round()}%',
                        style: TextStyle(fontSize: 12.5, color: ctx.appTextMuted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct.clamp(0.0, 1.0),
                      minHeight: 6,
                      backgroundColor: ctx.appChipIdleBg,
                      valueColor: AlwaysStoppedAnimation<Color>(cor),
                    ),
                  ),
                ],
              ),
            );
          }),
          if (grupos.length > 8)
            Text(
              '… e mais ${grupos.length - 8} categoria(s).',
              style: TextStyle(fontSize: 12, color: ctx.appTextMuted),
            ),
        ],
      ),
    );
  }

  // ─────────────────────────── avisos ───────────────────────────

  Widget _avisos(BuildContext ctx) {
    final repetidos = _lote.itens.where((i) => i.repetido).length;
    final pagamentos = _lote.itens.where((i) => i.pagamentoFatura).length;
    final avisos = <(IconData, Color, String)>[
      if (repetidos > 0)
        (
          Icons.copy_all_rounded,
          const Color(0xFFD97706),
          '$repetidos já ${repetidos == 1 ? 'está' : 'estão'} no app — '
              'deixei desmarcado para não duplicar.',
        ),
      if (pagamentos > 0)
        (
          Icons.credit_score_rounded,
          const Color(0xFF6366F1),
          '$pagamentos «pagamento da fatura» — pagar o cartão não é receita. '
              'Deixei desmarcado; se marcar, entra fora dos totais.',
        ),
      if (_lote.cortado)
        (
          Icons.filter_list_rounded,
          ctx.appTextMuted,
          'O arquivo tem ${_lote.total}; trouxe os primeiros ${_lote.itens.length}.',
        ),
    ];
    if (avisos.isEmpty) return const SizedBox(height: 4);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: avisos
            .map((a) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(a.$1, size: 16, color: a.$2),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          a.$3,
                          style: TextStyle(fontSize: 12.5, color: ctx.appTextSecondary),
                        ),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  // ─────────────────────────── linha ───────────────────────────

  Widget _linha(BuildContext ctx, int i, ExtratoItem item) {
    final apagado = !item.marcado;
    final cor = item.credito ? _verde : _vermelho;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: _gravando ? null : () => setState(() => item.marcado = !item.marcado),
          child: Ink(
            decoration: BoxDecoration(
              color: apagado ? ctx.appChipIdleBg : ctx.appSurface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: apagado ? ctx.appBorderSubtle : cor.withValues(alpha: 0.35),
              ),
            ),
            padding: const EdgeInsets.fromLTRB(8, 10, 12, 10),
            child: Row(
              children: [
                Checkbox(
                  value: item.marcado,
                  onChanged: _gravando
                      ? null
                      : (v) => setState(() => item.marcado = v ?? false),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.descricao,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: apagado ? ctx.appTextMuted : ctx.appTextPrimary,
                          decoration: item.repetido || item.pagamentoFatura
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            _ddmm(item.data),
                            style: TextStyle(fontSize: 12, color: ctx.appTextMuted),
                          ),
                          const SizedBox(width: 8),
                          Flexible(child: _chipCategoria(ctx, item)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${item.credito ? '+' : '−'} ${_money(item.valor)}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: apagado ? ctx.appTextMuted : cor,
                  ),
                ),
                IconButton(
                  tooltip: 'Editar',
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.edit_rounded, size: 18, color: ctx.appTextMuted),
                  onPressed: _gravando ? null : () => _editarLinha(i),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _chipCategoria(BuildContext ctx, ExtratoItem item) {
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: _gravando ? null : () => _trocarCategoria(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(
          color: ctx.appChipIdleBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: ctx.appChipIdleBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                item.categoria.isEmpty ? 'Escolher' : item.categoria,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: ctx.appChipIdleLabel),
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.expand_more_rounded, size: 13, color: ctx.appTextMuted),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── rodapé ───────────────────────────

  Widget _rodape(BuildContext ctx) {
    final n = _marcados.length;
    final cor = _lote.fatura ? const Color(0xFF7C3AED) : const Color(0xFF0D9488);
    final rotulo = _gravando
        ? 'Gravando…'
        : n == 0
            ? 'Nada marcado'
            : 'Gravar $n lançamento${n == 1 ? '' : 's'}';
    return Container(
      decoration: BoxDecoration(
        color: ctx.appSurface,
        border: Border(top: BorderSide(color: ctx.appBorderSubtle)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _gravando ? null : () => Navigator.of(context).pop(false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: ctx.appTextPrimary,
                  side: BorderSide(color: ctx.appChipIdleBorder),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Cancelar'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                onPressed: (n == 0 || _gravando) ? null : _confirmar,
                style: FilledButton.styleFrom(
                  backgroundColor: cor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _gravando
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(rotulo, overflow: TextOverflow.ellipsis),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────── ações ───────────────────────────

  void _alternarTodos() {
    final ligar = _marcados.length != _lote.itens.length;
    setState(() {
      for (final i in _lote.itens) {
        i.marcado = ligar;
      }
    });
  }

  /// Fatura × extrato: troca o sinal de todos de uma vez.
  ///
  /// A detecção é palpite (o CSV do Nubank não diz que é fatura), então o
  /// usuário precisa do botão — e trocar o sinal é mais honesto que pedir
  /// para ele reenviar o arquivo.
  void _trocarTipo() {
    final marcas = _lote.itens.map((i) => i.marcado).toList();
    final virado = _lote.inverterTipo();
    for (var k = 0; k < virado.itens.length; k++) {
      virado.itens[k].marcado = marcas[k];
      virado.itens[k].repetido = _lote.itens[k].repetido;
      // A categoria foi escolhida sabendo se era receita ou despesa; ao virar,
      // ela deixa de valer. Vazio é honesto — o chip pede a escolha.
      virado.itens[k].categoria = '';
    }
    setState(() => _lote = virado);
  }

  /// Edita a linha antes de gravar: descrição, valor, data e o tipo.
  ///
  /// O OCR erra um dígito; a descrição do banco vem «PAG*JOSEDASILVA». Corrigir
  /// aqui evita gravar errado e depois abrir lançamento por lançamento.
  Future<void> _editarLinha(int i) async {
    final atual = _lote.itens[i];
    final editado = await showModalBottomSheet<ExtratoItem>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => DecoratedBox(
        decoration: c.appSheetDecoration(),
        child: _EditarLinhaSheet(item: atual),
      ),
    );
    if (editado == null || !mounted) return;
    setState(() {
      // Trocar receita × despesa invalida a categoria escolhida para o outro
      // tipo; o chip pede a escolha de novo.
      final mudouTipo = editado.credito != atual.credito;
      _lote.itens[i] = editado.copyWith(categoria: mudouTipo ? '' : editado.categoria);
    });
  }

  Future<void> _trocarCategoria(ExtratoItem item) async {
    final opcoes = item.credito ? widget.categoriasReceita : widget.categoriasDespesa;
    final escolhida = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (c) => DecoratedBox(
        decoration: c.appSheetDecoration(),
        child: _EscolherCategoriaSheet(
          opcoes: opcoes,
          atual: item.categoria,
          receita: item.credito,
        ),
      ),
    );
    if (escolhida == null || !mounted) return;
    setState(() => item.categoria = escolhida);
  }

  Future<void> _confirmar() async {
    final marcados = _marcados;
    if (marcados.isEmpty) return;
    setState(() => _gravando = true);
    try {
      await widget.onConfirmar(marcados, _lote.fatura);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _gravando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não deu para gravar: $e')),
      );
    }
  }
}

/// Folha de escolha de categoria, com busca.
class _EscolherCategoriaSheet extends StatefulWidget {
  const _EscolherCategoriaSheet({
    required this.opcoes,
    required this.atual,
    required this.receita,
  });

  final List<String> opcoes;
  final String atual;
  final bool receita;

  @override
  State<_EscolherCategoriaSheet> createState() => _EscolherCategoriaSheetState();
}

class _EscolherCategoriaSheetState extends State<_EscolherCategoriaSheet> {
  final _busca = TextEditingController();

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    final termo = extratoSemAcento(_busca.text.toLowerCase()).trim();
    final lista = termo.isEmpty
        ? widget.opcoes
        : widget.opcoes
            .where((c) => extratoSemAcento(c.toLowerCase()).contains(termo))
            .toList();
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: ctx.appBorderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: TextField(
                controller: _busca,
                autofocus: false,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search_rounded),
                  hintText: widget.receita ? 'Categoria da receita' : 'Categoria da despesa',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: lista.length,
                itemBuilder: (context, i) {
                  final c = lista[i];
                  return ListTile(
                    title: Text(c, style: TextStyle(color: ctx.appTextPrimary)),
                    trailing: c == widget.atual
                        ? Icon(Icons.check_rounded, color: ctx.appNeon)
                        : null,
                    onTap: () => Navigator.pop(context, c),
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

/// Folha de edição de uma linha do extrato.
///
/// Limites iguais aos do lançamento: descrição até
/// [kExtratoDescricaoMax] — o mesmo da ficha do lançamento.
class _EditarLinhaSheet extends StatefulWidget {
  const _EditarLinhaSheet({required this.item});
  final ExtratoItem item;

  @override
  State<_EditarLinhaSheet> createState() => _EditarLinhaSheetState();
}

class _EditarLinhaSheetState extends State<_EditarLinhaSheet> {
  late final _descricao = TextEditingController(text: widget.item.descricao);
  late final _valor =
      TextEditingController(text: CurrencyFormats.formatBRLInput(widget.item.valor));
  late DateTime _data = widget.item.data;
  late bool _receita = widget.item.credito;

  @override
  void dispose() {
    _descricao.dispose();
    _valor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    final valor = CurrencyFormats.parseBRLInput(_valor.text) ?? 0;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Editar lançamento',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900, color: ctx.appTextPrimary)),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Despesa'), icon: Icon(Icons.trending_down_rounded)),
                ButtonSegment(value: true, label: Text('Receita'), icon: Icon(Icons.trending_up_rounded)),
              ],
              selected: {_receita},
              onSelectionChanged: (s) => setState(() => _receita = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descricao,
              maxLength: kExtratoDescricaoMax,
              style: TextStyle(color: ctx.appTextPrimary),
              decoration: const InputDecoration(
                labelText: 'Descrição',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _valor,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: CurrencyFormats.brlInputFormatters,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Valor',
                prefixText: 'R\$ ',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _data,
                  firstDate: DateTime(2000),
                  lastDate: DateTime(2100),
                );
                if (d != null && mounted) setState(() => _data = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                  labelText: 'Data',
                  prefixIcon: Icon(Icons.event_rounded, size: 20),
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                child: Text(
                  '${_data.day.toString().padLeft(2, '0')}/${_data.month.toString().padLeft(2, '0')}/${_data.year}',
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: ctx.appNeon, foregroundColor: ctx.appNeonOn),
                  onPressed: valor <= 0
                      ? null
                      : () => Navigator.pop(
                            context,
                            widget.item.copyWith(
                              descricao: _descricao.text.trim().isEmpty ? widget.item.descricao : _descricao.text.trim(),
                              valor: valor,
                              data: _data,
                              credito: _receita,
                            ),
                          ),
                  child: const Text('Aplicar'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
