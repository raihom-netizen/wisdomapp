import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr/qr.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../constants/currency_formats.dart';
import '../constants/finance_account_visuals.dart';
import '../models/finance_account.dart';
import '../screens/finance_accounts_screen.dart'
    show abrirEditorContaFinanceira, abrirNovaContaFinanceira;
import '../services/finance_accounts_service.dart';
import '../services/finance_pix_service.dart';
import '../utils/firestore_user_doc_id.dart';
import 'finance_confirm_payment_sheet.dart';
import '../theme/theme_context.dart';
import 'brl_amount_text_field.dart';
import 'finance_bank_brand_thumb.dart';
import 'pix_seletor.dart';

const _kPixVerde = Color(0xFF0D9488);
const _kPixVerde2 = Color(0xFF14B8A6);

/// «Cobrar com Pix» / «Receber Pix» — port do Controle Total (folha do Vendas)
/// para o Financeiro do WISDOMAPP, sem servidor:
///
/// - escolhe o banco e a chave (o Pix padrão do app já vem marcado);
/// - gera NO APARELHO o QR Code e o Pix copia e cola (BR Code com o valor);
/// - envia por WhatsApp/Telegram, copia ou compartilha;
/// - com [onConfirmarRecebimento] (receita pendente), mostra o botão
///   «Confirmar recebimento», que faz a baixa pelo fluxo normal do Financeiro.
///
/// Não há baixa automática (o WISDOMAPP não tem integração de recebimento).
Future<void> abrirCobrarPix(
  BuildContext context,
  String uid, {
  double? valor,
  String descricao = '',
  String contaSugerida = '',
  Future<bool> Function(BuildContext context)? onConfirmarRecebimento,
}) {
  return Navigator.of(context).push<void>(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _CobrarPixPage(
      uid: uid,
      valor: valor,
      descricao: descricao,
      contaSugerida: contaSugerida,
      onConfirmarRecebimento: onConfirmarRecebimento,
    ),
  ));
}

/// Baixa padrão de uma RECEITA pendente (mesma folha «Confirmar
/// recebimento» do Financeiro: data, horário, conta e comprovante). Usada
/// pelo «Receber Pix» onde a tela não tem a própria confirmação (ficha do
/// lançamento). Devolve true se confirmou.
Future<bool> confirmarRecebimentoPadrao(
  BuildContext context, {
  required String uid,
  required String docId,
  required Map<String, dynamic> dados,
  bool canAttachReceipt = true,
}) async {
  final contas = await FinanceAccountsService().listOnce(uid);
  if (!context.mounted) return false;
  final aid = (dados['financeAccountId'] ?? '').toString().trim();
  final r = await showFinanceConfirmPaymentSheet(
    context: context,
    isIncome: true,
    financeAccounts: contas,
    initialFinanceAccountId: aid.isEmpty ? null : aid,
    orphanAccountId: aid,
    canAttachReceipt: canAttachReceipt,
    amountPreview: (dados['amount'] as num?)?.toDouble(),
    categoryPreview: (dados['category'] ?? '').toString(),
    descriptionPreview: (dados['description'] ?? '').toString(),
  );
  if (r == null || !context.mounted) return false;
  final messenger = ScaffoldMessenger.maybeOf(context);
  try {
    await commitFinanceConfirmPayment(
      txRef: FirebaseFirestore.instance
          .collection('users')
          .doc(firestoreUserDocIdForAppShell(uid))
          .collection('transactions')
          .doc(docId),
      uid: uid,
      result: r,
    );
    messenger?.showSnackBar(const SnackBar(
      content: Text('Recebimento confirmado.'),
      behavior: SnackBarBehavior.floating,
    ));
    return true;
  } catch (e) {
    messenger?.showSnackBar(SnackBar(
      content: Text('Erro ao confirmar: ${e.toString().split('\n').first}'),
      backgroundColor: const Color(0xFFDC2626),
    ));
    return false;
  }
}

/// «Meu Pix»: bancos e chaves Pix (ficam no cadastro de cada banco) + cidade.
Future<void> abrirMeuPix(BuildContext context, String uid) {
  return Navigator.of(context).push<void>(MaterialPageRoute<void>(
    fullscreenDialog: true,
    builder: (_) => _MeuPixPage(uid: uid),
  ));
}

void _toast(BuildContext context, String msg, {bool erro = false}) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
    content: Text(msg),
    behavior: SnackBarBehavior.floating,
    backgroundColor: erro ? const Color(0xFFDC2626) : null,
  ));
}

// ── Cobrar ──────────────────────────────────────────────────────────────────

class _CobrarPixPage extends StatefulWidget {
  const _CobrarPixPage({
    required this.uid,
    this.valor,
    this.descricao = '',
    this.contaSugerida = '',
    this.onConfirmarRecebimento,
  });

  final String uid;
  final double? valor;
  final String descricao;
  final String contaSugerida;
  final Future<bool> Function(BuildContext context)? onConfirmarRecebimento;

  @override
  State<_CobrarPixPage> createState() => _CobrarPixPageState();
}

class _CobrarPixPageState extends State<_CobrarPixPage> {
  final _valor = TextEditingController();
  final _descricao = TextEditingController();

  FinancePixDados? _dados;
  List<PixOpcao> _opcoes = const [];
  PixOpcao? _pixSel;
  bool _carregando = true;
  bool _semChave = false;
  bool _confirmando = false;
  String _erro = '';

  /// Pix gerado (null = ainda no formulário).
  ({String codigo, double valor, FinancePixInfo info})? _gerado;

  bool get _valorFixo => (widget.valor ?? 0) > 0;

  @override
  void initState() {
    super.initState();
    if (_valorFixo) {
      _valor.text = CurrencyFormats.formatBRLInput(widget.valor!);
    }
    _descricao.text = widget.descricao.trim();
    unawaited(_carregar(gerarDepois: _valorFixo));
  }

  @override
  void dispose() {
    _valor.dispose();
    _descricao.dispose();
    super.dispose();
  }

  Future<void> _carregar({bool gerarDepois = false}) async {
    setState(() {
      _carregando = true;
      _erro = '';
    });
    try {
      final d = await FinancePixService.instance.carregarDados(widget.uid);
      final ops = FinancePixService.opcoesDosDados(d);
      final pp = FinancePixService.pixPadraoDosDados(d);
      PixOpcao? sel;
      // Sem Pix padrão do app, a receita ligada a um banco cobra nesse banco.
      if (pp == null && widget.contaSugerida.isNotEmpty) {
        for (final o in ops) {
          if (o.conta.id == widget.contaSugerida && o.padraoDaConta) sel = o;
        }
      }
      sel ??= ops.where((o) => o.selecionadaSozinha).firstOrNull ?? ops.firstOrNull;
      if (!mounted) return;
      setState(() {
        _dados = d;
        _opcoes = ops;
        _pixSel = sel;
        _semChave = ops.isEmpty;
        _carregando = false;
      });
      if (gerarDepois && !_semChave) _gerar();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _carregando = false;
        _erro = 'Não consegui carregar seus bancos agora. Confira a internet e tente de novo.';
      });
    }
  }

  double get _valorDigitado => CurrencyFormats.parseBRLInput(_valor.text) ?? 0;

  void _gerar() {
    final valor = _valorDigitado;
    if (valor <= 0) {
      setState(() => _erro = 'Informe o valor.');
      return;
    }
    final d = _dados;
    if (d == null) return;
    final sel = _pixSel;
    final info = FinancePixService.pixDosDados(
      d,
      contaId: sel?.conta.id ?? '',
      chave: sel?.chave ?? '',
      contaSugerida: widget.contaSugerida,
    );
    if (info == null) {
      setState(() => _semChave = true);
      return;
    }
    FocusScope.of(context).unfocus();
    final codigo = FinancePixService.codigoPix(info, valor: valor, descricao: _descricao.text.trim());
    setState(() {
      _erro = '';
      _gerado = (codigo: codigo, valor: valor, info: info);
    });
  }

  Future<void> _trocarPix() async {
    if (_opcoes.isEmpty) {
      await abrirMeuPix(context, widget.uid);
      await _carregar();
      return;
    }
    final r = await escolherPix(context, uid: widget.uid, opcoes: _opcoes, atual: _pixSel);
    if (r == null || !mounted) return;
    setState(() => _pixSel = r.opcao);
    if (r.virouPadrao) unawaited(_carregar());
    // Já tinha gerado: gera de novo com a chave nova.
    if (_gerado != null) _gerar();
  }

  String _mensagem() {
    final g = _gerado!;
    return FinancePixService.mensagem(
      info: g.info,
      codigo: g.codigo,
      valorFormatado: CurrencyFormats.formatBRL(g.valor),
      descricao: _descricao.text,
    );
  }

  Future<void> _whatsApp() async {
    final uri = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(_mensagem())}');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _telegram() async {
    final g = _gerado!;
    final uri = Uri.parse(
      'https://t.me/share/url?url=${Uri.encodeComponent(g.codigo)}&text=${Uri.encodeComponent(_mensagem())}',
    );
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copiar(String texto, String aviso) async {
    await Clipboard.setData(ClipboardData(text: texto));
    if (mounted) _toast(context, aviso);
  }

  Future<void> _confirmarRecebimento() async {
    final cb = widget.onConfirmarRecebimento;
    if (cb == null) return;
    setState(() => _confirmando = true);
    final ok = await cb(context);
    if (!mounted) return;
    setState(() => _confirmando = false);
    if (ok) Navigator.of(context).maybePop();
  }

  void _novaCobranca() {
    setState(() {
      _gerado = null;
      _erro = '';
      if (!_valorFixo) {
        _valor.clear();
        _descricao.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final g = _gerado;
    final receber = widget.onConfirmarRecebimento != null;
    return Scaffold(
      backgroundColor: context.appScaffold,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: _kPixVerde,
        title: Text(receber ? 'Receber Pix' : 'Cobrar com Pix',
            style: const TextStyle(fontWeight: FontWeight.w900)),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF065F46), _kPixVerde, _kPixVerde2]),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Meu Pix (chaves)',
            onPressed: () async {
              await abrirMeuPix(context, widget.uid);
              await _carregar();
            },
            icon: const Icon(Icons.key_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 24 + MediaQuery.viewInsetsOf(context).bottom),
          children: [
            _Cabecalho(
              icone: receber ? Icons.call_received_rounded : Icons.qr_code_2_rounded,
              titulo: receber ? 'Receber esta receita por Pix' : 'Gerar Pix',
              subtitulo: 'QR Code e copia e cola gerados no aparelho, com a sua chave',
            ),
            const SizedBox(height: 14),
            if (_carregando)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (g == null) ...[
              _Secao(
                titulo: 'Cobrança',
                icone: Icons.payments_rounded,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  BrlAmountTextField(
                    controller: _valor,
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
                    decoration: const InputDecoration(
                      labelText: 'Valor',
                      prefixText: 'R\$ ',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _descricao,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Referente a (opcional)',
                      hintText: 'Ex.: aluguel de outubro',
                      prefixIcon: Icon(Icons.notes_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ]),
              ),
              _Secao(
                titulo: 'Recebe em',
                icone: Icons.account_balance_rounded,
                child: _pixSel != null
                    ? PixEscolhidoFaixa(opcao: _pixSel!, total: _opcoes.length, onTrocar: _trocarPix)
                    : OutlinedButton.icon(
                        onPressed: _trocarPix,
                        icon: const Icon(Icons.key_rounded),
                        label: const Text('Escolher / cadastrar chave Pix'),
                      ),
              ),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: _kPixVerde,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: _gerar,
                icon: const Icon(Icons.bolt_rounded),
                label: const Text('Gerar Pix', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
            ],
            if (_erro.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(_erro,
                    style: TextStyle(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600)),
              ),
            if (_semChave && !_carregando) ...[
              const SizedBox(height: 10),
              _AvisoSemChave(onCadastrar: () async {
                await abrirMeuPix(context, widget.uid);
                await _carregar(gerarDepois: _valorDigitado > 0);
              }),
            ],
            if (g != null) ...[
              if (_pixSel != null) ...[
                PixEscolhidoFaixa(opcao: _pixSel!, total: _opcoes.length, onTrocar: _trocarPix),
                const SizedBox(height: 10),
              ],
              _CartaoCobranca(codigo: g.codigo, valor: g.valor, info: g.info),
              const SizedBox(height: 14),
              if (receber) ...[
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF15803D),
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: _confirmando ? null : _confirmarRecebimento,
                  icon: _confirmando
                      ? const SizedBox(
                          width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.task_alt_rounded),
                  label: const Text('Confirmar recebimento', style: TextStyle(fontWeight: FontWeight.w900)),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 10),
                  child: Text(
                    'Quando o Pix cair na sua conta, confirme aqui: a receita sai dos pendentes e entra no saldo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: context.appTextSecondary),
                  ),
                ),
              ],
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: _whatsApp,
                icon: const Icon(Icons.chat_rounded),
                label: const Text('Enviar pelo WhatsApp', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF229ED9),
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: _telegram,
                icon: const Icon(Icons.send_rounded),
                label: const Text('Enviar pelo Telegram', style: TextStyle(fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copiar(g.codigo, 'Pix copia e cola copiado.'),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copia e cola'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _copiar(g.info.chave, 'Chave Pix copiada.'),
                    icon: const Icon(Icons.key_rounded, size: 18),
                    label: const Text('Chave'),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Compartilhar',
                  onPressed: () => Share.share(_mensagem(), subject: 'Pagamento Pix'),
                  icon: const Icon(Icons.share_rounded),
                ),
              ]),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _novaCobranca,
                icon: Icon(_valorFixo ? Icons.edit_rounded : Icons.add_rounded),
                label: Text(_valorFixo ? 'Alterar valor ou descrição' : 'Nova cobrança'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Cabecalho extends StatelessWidget {
  const _Cabecalho({required this.icone, required this.titulo, required this.subtitulo});

  final IconData icone;
  final String titulo;
  final String subtitulo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Color(0xFF064E3B), _kPixVerde, _kPixVerde2]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(14)),
          child: Icon(icone, color: Colors.white, size: 28),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(titulo, style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(subtitulo,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }
}

class _Secao extends StatelessWidget {
  const _Secao({required this.titulo, required this.icone, required this.child});

  final String titulo;
  final IconData icone;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _kPixVerde.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(color: _kPixVerde.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(icone, size: 18, color: _kPixVerde),
          const SizedBox(width: 6),
          Text(titulo,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: _kPixVerde)),
        ]),
        const SizedBox(height: 10),
        child,
      ]),
    );
  }
}

class _CartaoCobranca extends StatelessWidget {
  const _CartaoCobranca({required this.codigo, required this.valor, required this.info});

  final String codigo;
  final double valor;
  final FinancePixInfo info;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _kPixVerde.withValues(alpha: 0.35)),
      ),
      child: Column(children: [
        Text(CurrencyFormats.formatBRL(valor),
            style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900, color: _kPixVerde)),
        if (info.titular.isNotEmpty)
          Text(info.titular, style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w600)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: SizedBox(width: 200, height: 200, child: PixQrCode(data: codigo)),
        ),
        const SizedBox(height: 10),
        Text(
          'Recebe em ${info.contaNome} · ${info.tipoChave} ${info.chave}',
          textAlign: TextAlign.center,
          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
        ),
        const SizedBox(height: 8),
        SelectableText(
          codigo,
          maxLines: 3,
          style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ]),
    );
  }
}

/// QR Code desenhado com o pacote `qr` (sem imagem externa) — igual ao CT.
class PixQrCode extends StatelessWidget {
  const PixQrCode({super.key, required this.data, this.cor = Colors.black});

  final String data;
  final Color cor;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _QrPainter(data, cor));
}

class _QrPainter extends CustomPainter {
  _QrPainter(this.data, this.cor)
      : _qr = QrImage(QrCode.fromData(data: data, errorCorrectLevel: QrErrorCorrectLevel.M));

  final String data;
  final Color cor;
  final QrImage _qr;

  @override
  void paint(Canvas canvas, Size size) {
    final n = _qr.moduleCount;
    final lado = size.shortestSide / n;
    final paint = Paint()
      ..color = cor
      ..isAntiAlias = false;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        if (_qr.isDark(y, x)) {
          canvas.drawRect(Rect.fromLTWH(x * lado, y * lado, lado + 0.5, lado + 0.5), paint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_QrPainter old) => old.data != data || old.cor != cor;
}

class _AvisoSemChave extends StatelessWidget {
  const _AvisoSemChave({required this.onCadastrar});

  final VoidCallback onCadastrar;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.isDarkMode
            ? context.appAccentSurface(const Color(0xFFEA580C))
            : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: context.isDarkMode
                ? const Color(0xFFEA580C).withValues(alpha: 0.5)
                : const Color(0xFFFDBA74)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.key_off_rounded,
              color: context.isDarkMode ? const Color(0xFFFDBA74) : const Color(0xFFC2410C)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Nenhuma chave Pix cadastrada',
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: context.isDarkMode ? const Color(0xFFFDBA74) : const Color(0xFF9A3412))),
          ),
        ]),
        const SizedBox(height: 6),
        Text(
          'A chave fica no cadastro do banco (Bancos e cartões). Cadastre uma — CPF, CNPJ, celular, '
          'e-mail ou aleatória — e o Pix sai com ela.',
          style: TextStyle(
              fontSize: 12.5,
              color: context.isDarkMode ? const Color(0xFFFED7AA) : const Color(0xFF7C2D12),
              height: 1.35),
        ),
        const SizedBox(height: 10),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEA580C)),
          onPressed: onCadastrar,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Cadastrar chave Pix'),
        ),
      ]),
    );
  }
}

// ── Meu Pix ─────────────────────────────────────────────────────────────────

class _MeuPixPage extends StatefulWidget {
  const _MeuPixPage({required this.uid});

  final String uid;

  @override
  State<_MeuPixPage> createState() => _MeuPixPageState();
}

class _MeuPixPageState extends State<_MeuPixPage> {
  late Future<FinancePixDados> _dados;
  final _cidade = TextEditingController();
  bool _cidadeCarregada = false;

  @override
  void initState() {
    super.initState();
    _dados = _carregar();
  }

  @override
  void dispose() {
    _cidade.dispose();
    super.dispose();
  }

  Future<FinancePixDados> _carregar() async {
    final d = await FinancePixService.instance.carregarDados(widget.uid);
    if (!_cidadeCarregada) {
      _cidade.text = FinancePixService.cidadeDosDados(d);
      _cidadeCarregada = true;
    }
    return d;
  }

  void _recarregar() => setState(() => _dados = _carregar());

  Future<void> _editar(FinanceAccount conta) async {
    await abrirEditorContaFinanceira(context, uid: widget.uid, account: conta);
    if (mounted) _recarregar();
  }

  Future<void> _novoBanco() async {
    await abrirNovaContaFinanceira(context, uid: widget.uid);
    if (mounted) _recarregar();
  }

  Future<void> _definirPrincipal(FinanceAccount conta) async {
    if (conta.chavesPix.isEmpty) return;
    try {
      await FinancePixService.instance.definirPixPadrao(widget.uid, conta.id, conta.chavesPix.first);
      if (!mounted) return;
      _toast(context, '${conta.displayName} agora é o Pix padrão do app.');
      _recarregar();
    } catch (_) {
      if (mounted) _toast(context, 'Não consegui definir o padrão agora.', erro: true);
    }
  }

  Future<void> _salvarCidade() async {
    try {
      await FinancePixService.instance.definirCidade(widget.uid, _cidade.text);
      if (mounted) _toast(context, 'Cidade do Pix salva.');
    } catch (_) {
      if (mounted) _toast(context, 'Não consegui salvar a cidade agora.', erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appScaffold,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: _kPixVerde,
        title: const Text('Meu Pix', style: TextStyle(fontWeight: FontWeight.w900)),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF065F46), _kPixVerde, _kPixVerde2]),
          ),
        ),
      ),
      body: SafeArea(
        child: FutureBuilder<FinancePixDados>(
          future: _dados,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: TextButton.icon(
                  onPressed: _recarregar,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Não consegui carregar os bancos. Tentar de novo'),
                ),
              );
            }
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final d = snap.data!;
            final contas = d.contas.where(FinancePixService.recebePix).toList();
            final pp = FinancePixService.pixPadraoDosDados(d);
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                const _Cabecalho(
                  icone: Icons.key_rounded,
                  titulo: 'Meu Pix',
                  subtitulo: 'As chaves ficam no cadastro de cada banco e vão nas cobranças',
                ),
                const SizedBox(height: 12),
                _Secao(
                  titulo: 'Cidade do recebedor',
                  icone: Icons.location_city_rounded,
                  child: Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _cidade,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Cidade (vai no código Pix)',
                          hintText: 'Ex.: Goiânia',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: _kPixVerde),
                      onPressed: _salvarCidade,
                      child: const Text('Salvar'),
                    ),
                  ]),
                ),
                if (contas.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(children: [
                      Icon(Icons.account_balance_rounded, size: 46, color: context.appTextMuted),
                      const SizedBox(height: 10),
                      Text(
                        'Você ainda não tem banco cadastrado.\nCadastre um aqui mesmo para receber por Pix.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: context.appTextSecondary),
                      ),
                    ]),
                  ),
                for (final c in contas)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _LinhaBancoPix(
                      conta: c,
                      principal: pp?.contaId == c.id,
                      onEditar: () => _editar(c),
                      onPrincipal: pp?.contaId == c.id || c.chavesPix.isEmpty ? null : () => _definirPrincipal(c),
                    ),
                  ),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _novoBanco,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kPixVerde,
                    minimumSize: const Size.fromHeight(48),
                    side: BorderSide(color: _kPixVerde.withValues(alpha: 0.5)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Novo banco', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _kPixVerde, minimumSize: const Size.fromHeight(50)),
                  onPressed: () {
                    final nav = Navigator.of(context);
                    nav.pop();
                    abrirCobrarPix(nav.context, widget.uid);
                  },
                  icon: const Icon(Icons.qr_code_2_rounded),
                  label: const Text('Gerar Pix', style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _LinhaBancoPix extends StatelessWidget {
  const _LinhaBancoPix({
    required this.conta,
    required this.principal,
    required this.onEditar,
    this.onPrincipal,
  });

  final FinanceAccount conta;
  final bool principal;
  final VoidCallback onEditar;
  final VoidCallback? onPrincipal;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final vis = financeAccountVisualFor(conta);
    final chaves = conta.chavesPix;
    final temChave = chaves.isNotEmpty;
    final titular = (conta.holderName ?? '').trim();
    Widget selo(String t, Color c, {IconData? icone}) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color: c.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: c.withValues(alpha: 0.35)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icone != null) ...[Icon(icone, size: 12, color: c), const SizedBox(width: 3)],
            Text(t, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: c)),
          ]),
        );
    return Material(
      color: temChave ? _kPixVerde.withValues(alpha: 0.10) : cs.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onEditar,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 46,
              height: 46,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: vis.gradient.length >= 2 ? vis.gradient.sublist(0, 2) : [vis.color, vis.color],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: FinanceBankBrandThumb(preset: conta.preset, size: 30, fallbackIcon: vis.icon),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(conta.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 3),
                Wrap(spacing: 6, runSpacing: 4, children: [
                  if (principal) selo('Pix padrão', const Color(0xFFD97706), icone: Icons.star_rounded),
                  selo(temChave ? 'com Pix' : 'sem Pix', temChave ? _kPixVerde : const Color(0xFF64748B),
                      icone: temChave ? Icons.key_rounded : Icons.key_off_rounded),
                  selo(conta.productTypeLabel, const Color(0xFF2563EB)),
                ]),
                const SizedBox(height: 4),
                if (!temChave)
                  Text('Sem chave Pix — toque para cadastrar',
                      style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant))
                else
                  for (final k in chaves)
                    Text('${FinancePixService.tipoDaChave(k)}: $k${k == chaves.first ? '  ★' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                if (temChave && titular.isNotEmpty)
                  Text('Titular: $titular',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
              ]),
            ),
            IconButton(tooltip: 'Editar banco', onPressed: onEditar, icon: const Icon(Icons.edit_rounded)),
            PopupMenuButton<String>(
              tooltip: 'Mais opções',
              onSelected: (v) async {
                switch (v) {
                  case 'principal':
                    onPrincipal?.call();
                  case 'copiar':
                    await Clipboard.setData(ClipboardData(text: chaves.first));
                    if (context.mounted) _toast(context, 'Chave Pix copiada.');
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'principal',
                  enabled: onPrincipal != null,
                  child: const ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.star_rounded),
                    title: Text('Definir como Pix padrão'),
                  ),
                ),
                PopupMenuItem(
                  value: 'copiar',
                  enabled: temChave,
                  child: const ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.copy_rounded),
                    title: Text('Copiar chave'),
                  ),
                ),
              ],
            ),
          ]),
        ),
      ),
    );
  }
}
