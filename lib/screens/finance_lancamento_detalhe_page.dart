import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../constants/currency_formats.dart';
import '../constants/finance_bank_presets.dart';
import '../theme/theme_context.dart';
import '../utils/finance_transaction_historico.dart';
import '../utils/firestore_user_doc_id.dart';
import '../widgets/finance_pix_sheets.dart';

const _kVerde = Color(0xFF059669);
const _kVermelho = Color(0xFFDC2626);
const _kAmbar = Color(0xFFB45309);

/// A ficha completa de um lançamento: tudo que ele guarda, a observação e a
/// história dele.
///
/// Duas coisas não existiam no app e são o motivo desta tela:
///
/// **Observação.** O único texto livre era a `description`, que é o *o quê*
/// («Supermercado Bom Preço»). Faltava o *por quê* («foi a compra do mês da
/// casa da minha mãe, ela me devolve»). Misturar os dois faz a pessoa não
/// anotar nada — ou poluir a descrição e depois não achar o lançamento na
/// busca.
///
/// **Histórico.** Existe uma auditoria global (`activity_logs`), mas ela não
/// guarda o id do documento — era impossível olhar um lançamento e saber se
/// ele veio do banco, do bot, de uma venda, ou se alguém mexeu na categoria.
/// A linha do tempo aqui é montada do que o próprio documento já carrega
/// (`finance_transaction_historico.dart`), sem coleção nova.
class FinanceLancamentoDetalhePage extends StatefulWidget {
  const FinanceLancamentoDetalhePage({
    super.key,
    required this.uid,
    required this.docId,
    required this.dados,
  });

  final String uid;
  final String docId;
  final Map<String, dynamic> dados;

  static Future<void> abrir(
    BuildContext context, {
    required String uid,
    required String docId,
    required Map<String, dynamic> dados,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FinanceLancamentoDetalhePage(uid: uid, docId: docId, dados: dados),
      ),
    );
  }

  @override
  State<FinanceLancamentoDetalhePage> createState() => _FinanceLancamentoDetalhePageState();
}

class _FinanceLancamentoDetalhePageState extends State<FinanceLancamentoDetalhePage> {
  late final TextEditingController _obs =
      TextEditingController(text: '${widget.dados['observacao'] ?? ''}');
  bool _salvando = false;
  String _obsSalva = '';

  @override
  void initState() {
    super.initState();
    _obsSalva = _obs.text;
  }

  @override
  void dispose() {
    _obs.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _d => widget.dados;

  bool get _receita => '${_d['type']}' == 'income';
  bool get _pago => '${_d['status']}' == 'paid';
  double get _valor => (_d['amount'] as num?)?.toDouble() ?? 0;

  String _txt(dynamic v) => (v ?? '').toString().trim();

  DateTime? _data(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    return DateTime.tryParse('$v');
  }

  static String _dmaHora(DateTime? d) {
    if (d == null) return '—';
    final dd = d.day.toString().padLeft(2, '0');
    final mm = d.month.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final mi = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year} às $hh:$mi';
  }

  static String _dma(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  Future<void> _salvarObservacao() async {
    final texto = _obs.text.trim();
    setState(() => _salvando = true);
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(firestoreUserDocIdForAppShell(widget.uid))
          .collection('transactions')
          .doc(widget.docId)
          .set({
        'observacao': texto,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _obsSalva = texto;
        _salvando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Observação salva.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _salvando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Não consegui salvar agora. Tente de novo.'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cor = _receita ? _kVerde : _kVermelho;
    final historico = financeHistoricoDoLancamento(_d);

    return Scaffold(
      backgroundColor: context.appScaffold,
      appBar: AppBar(
        title: const Text('Detalhe do lançamento'),
        backgroundColor: cor,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _cabecalho(cor),
          const SizedBox(height: 12),
          _cardCampos(),
          // Receita ainda não recebida: o Pix da cobrança sai daqui
          // (QR Code + copia e cola); confirmar dá a baixa normal.
          if (_receita && !_pago) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => abrirCobrarPix(
                  context,
                  widget.uid,
                  valor: _valor,
                  descricao: _txt(_d['description']).isEmpty
                      ? _txt(_d['category'])
                      : _txt(_d['description']),
                  contaSugerida: _txt(_d['financeAccountId']),
                  onConfirmarRecebimento: (c) => confirmarRecebimentoPadrao(
                    c,
                    uid: widget.uid,
                    docId: widget.docId,
                    dados: _d,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.qr_code_2_rounded, size: 19),
                label: const Text('Receber via Pix'),
              ),
            ),
          ],
          const SizedBox(height: 12),
          _cardObservacao(),
          const SizedBox(height: 12),
          _cardHistorico(historico),
        ],
      ),
    );
  }

  Widget _cabecalho(Color cor) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cor, Color.lerp(cor, Colors.black, 0.28)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(_receita ? Icons.south_west_rounded : Icons.north_east_rounded,
                color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(_receita ? 'Receita' : 'Despesa',
                style: const TextStyle(
                    color: Colors.white70, fontWeight: FontWeight.w800, fontSize: 13)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(_pago ? (_receita ? 'RECEBIDO' : 'PAGO') : 'PENDENTE',
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w900, fontSize: 10.5)),
            ),
          ]),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '${_receita ? '+' : '−'} ${CurrencyFormats.formatBRL(_valor)}',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900, fontSize: 30, height: 1.1),
            ),
          ),
          if (_txt(_d['description']).isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(_txt(_d['description']),
                style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.35)),
          ],
        ],
      ),
    );
  }

  Widget _cardCampos() {
    final conta = _txt(_d['financeAccountId']);
    final preset = financeBankPresetById(conta);
    final parcelas = (_d['installmentCount'] as num?)?.toInt() ?? 1;
    final linhas = <({String r, String v, IconData i})>[
      (r: 'Categoria', v: _txt(_d['category']).isEmpty ? '—' : _txt(_d['category']), i: Icons.label_rounded),
      (r: 'Data', v: _dma(_data(_d['date'])), i: Icons.event_rounded),
      if (_data(_d['effectiveDate']) != null)
        (r: 'Data efetiva', v: _dma(_data(_d['effectiveDate'])), i: Icons.event_available_rounded),
      if (preset != null) (r: 'Conta', v: preset.name, i: Icons.account_balance_rounded),
      if (parcelas > 1)
        (
          r: 'Parcela',
          v: '${(_d['installmentIndex'] as num?)?.toInt() ?? 1} de $parcelas',
          i: Icons.view_week_rounded
        ),
      if (_txt(_d['parceiroNome']).isNotEmpty)
        (r: 'Cliente / fornecedor', v: _txt(_d['parceiroNome']), i: Icons.person_rounded),
      if (_txt(_d['vendaRecibo']).isNotEmpty)
        (r: 'Recibo', v: _txt(_d['vendaRecibo']), i: Icons.receipt_long_rounded),
      if (_d['cartaoCredito'] == true)
        (r: 'Fatura', v: _txt(_d['faturaRef']), i: Icons.credit_card_rounded),
    ];

    return _cartao(
      titulo: 'O lançamento',
      icone: Icons.description_rounded,
      filhos: [
        for (final l in linhas)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(children: [
              Icon(l.i, size: 16, color: context.appTextMuted),
              const SizedBox(width: 9),
              Expanded(
                child: Text(l.r,
                    style: TextStyle(fontSize: 13, color: context.appTextSecondary)),
              ),
              Flexible(
                child: Text(l.v,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: context.appTextPrimary)),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _cardObservacao() {
    final mudou = _obs.text.trim() != _obsSalva.trim();
    return _cartao(
      titulo: 'Observação',
      icone: Icons.sticky_note_2_rounded,
      filhos: [
        Text(
          'A descrição diz o QUE foi. Aqui cabe o porquê — o detalhe que você '
          'vai querer lembrar daqui a seis meses.',
          style: TextStyle(fontSize: 12, height: 1.35, color: context.appTextSecondary),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _obs,
          maxLines: 4,
          minLines: 2,
          maxLength: 500,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            hintText: 'Ex.: compra do mês da casa da minha mãe, ela me devolve',
            filled: true,
            fillColor: context.appInputFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        if (mudou)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _salvando ? null : _salvarObservacao,
              icon: _salvando
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 18),
              label: const Text('Salvar observação'),
            ),
          ),
      ],
    );
  }

  Widget _cardHistorico(List<FinanceHistoricoItem> itens) {
    return _cartao(
      titulo: 'Histórico',
      icone: Icons.history_rounded,
      filhos: [
        if (itens.isEmpty)
          Text('Sem histórico registrado.',
              style: TextStyle(fontSize: 13, color: context.appTextSecondary))
        else
          for (var i = 0; i < itens.length; i++) _linhaHistorico(itens[i], i == itens.length - 1),
      ],
    );
  }

  Widget _linhaHistorico(FinanceHistoricoItem h, bool ultimo) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: h.cor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              child: Icon(h.icone, size: 16, color: h.cor),
            ),
            if (!ultimo)
              Expanded(
                child: Container(width: 2, color: context.appBorderSubtle),
              ),
          ]),
          const SizedBox(width: 11),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: ultimo ? 0 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(h.titulo,
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13.5,
                              color: context.appTextPrimary)),
                    ),
                    if (h.quando != null)
                      Text(_dmaHora(h.quando),
                          style: TextStyle(fontSize: 11, color: context.appTextMuted)),
                  ]),
                  const SizedBox(height: 2),
                  Text(h.detalhe,
                      style: TextStyle(
                          fontSize: 12.5, height: 1.35, color: context.appTextSecondary)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _cartao({
    required String titulo,
    required IconData icone,
    required List<Widget> filhos,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icone, size: 18, color: context.appTextSecondary),
            const SizedBox(width: 8),
            Text(titulo,
                style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 14, color: context.appTextPrimary)),
          ]),
          const SizedBox(height: 12),
          ...filhos,
        ],
      ),
    );
  }
}

/// Cor do selo de atraso (exportada para as listas reaproveitarem).
const Color kFinanceAtrasoCor = _kAmbar;
