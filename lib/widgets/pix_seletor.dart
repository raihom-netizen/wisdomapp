import 'package:flutter/material.dart';

import '../constants/finance_account_visuals.dart';
import '../services/finance_pix_service.dart';
import '../theme/theme_context.dart';
import 'finance_bank_brand_thumb.dart';

const _verdePix = Color(0xFF0D9488);

/// Faixa «Recebendo em: Nubank · CPF 945…» com o botão **Trocar** — mostra
/// qual Pix vai sair na cobrança antes de gerar, e deixa mudar de banco ou
/// de chave sem sair da tela.
class PixEscolhidoFaixa extends StatelessWidget {
  const PixEscolhidoFaixa({super.key, required this.opcao, required this.onTrocar, this.total = 1});

  final PixOpcao opcao;
  final VoidCallback onTrocar;

  /// Quantas chaves existem ao todo (com uma só, «Trocar» vira «Adicionar»).
  final int total;

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    final vis = financeAccountVisualFor(opcao.conta);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(colors: [
          Color.alphaBlend(_verdePix.withValues(alpha: 0.16), ctx.appSurface),
          Color.alphaBlend(vis.gradient.first.withValues(alpha: 0.10), ctx.appSurface),
        ]),
        border: Border.all(color: _verdePix.withValues(alpha: 0.45)),
      ),
      child: Row(children: [
        _Marca(opcao: opcao),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Recebendo em ${opcao.conta.displayName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13.5, color: ctx.appTextPrimary)),
            Text('${opcao.tipo} · ${opcao.chave}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: ctx.appTextSecondary)),
          ]),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: _verdePix,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onPressed: onTrocar,
          icon: const Icon(Icons.swap_horiz_rounded, size: 18),
          label: Text(total > 1 ? 'Trocar' : 'Ver'),
        ),
      ]),
    );
  }
}

class _Marca extends StatelessWidget {
  const _Marca({required this.opcao, this.tamanho = 40});
  final PixOpcao opcao;
  final double tamanho;

  @override
  Widget build(BuildContext context) {
    final vis = financeAccountVisualFor(opcao.conta);
    return Container(
      width: tamanho,
      height: tamanho,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: vis.gradient.length >= 2 ? vis.gradient.sublist(0, 2) : [vis.gradient.first, vis.gradient.first],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: FinanceBankBrandThumb(preset: opcao.conta.preset, size: tamanho * 0.64, fallbackIcon: vis.icon),
    );
  }
}

/// Resultado do seletor: a chave escolhida e se virou o Pix padrão do app.
class PixEscolha {
  PixEscolha(this.opcao, {this.virouPadrao = false});
  final PixOpcao opcao;
  final bool virouPadrao;
}

/// Tela cheia «Receber com qual Pix?»: todos os bancos e chaves, a atual
/// marcada. Rodapé com **Retornar**, **Usar esta** e **Usar e deixar padrão**.
Future<PixEscolha?> escolherPix(
  BuildContext context, {
  required String uid,
  required List<PixOpcao> opcoes,
  PixOpcao? atual,
}) {
  return Navigator.of(context).push<PixEscolha>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => _EscolherPixPage(uid: uid, opcoes: opcoes, atual: atual),
  ));
}

class _EscolherPixPage extends StatefulWidget {
  const _EscolherPixPage({required this.uid, required this.opcoes, this.atual});
  final String uid;
  final List<PixOpcao> opcoes;
  final PixOpcao? atual;

  @override
  State<_EscolherPixPage> createState() => _EscolherPixPageState();
}

class _EscolherPixPageState extends State<_EscolherPixPage> {
  late PixOpcao? _sel = widget.atual ?? (widget.opcoes.isEmpty ? null : widget.opcoes.first);
  bool _salvando = false;

  bool _igual(PixOpcao a, PixOpcao? b) => b != null && a.conta.id == b.conta.id && a.chave == b.chave;

  Future<void> _usar({required bool padrao}) async {
    final s = _sel;
    if (s == null) return;
    if (padrao) {
      setState(() => _salvando = true);
      try {
        await FinancePixService.instance.definirPixPadrao(widget.uid, s.conta.id, s.chave);
      } catch (_) {
        if (mounted) {
          setState(() => _salvando = false);
          ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Não consegui gravar o padrão agora. Tente de novo.')));
        }
        return;
      }
    }
    if (mounted) Navigator.of(context).pop(PixEscolha(s, virouPadrao: padrao));
  }

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    // Agrupa por banco, mantendo a ordem (o padrão vem primeiro).
    final grupos = <String, List<PixOpcao>>{};
    for (final o in widget.opcoes) {
      (grupos[o.conta.id] ??= []).add(o);
    }
    return Scaffold(
      backgroundColor: ctx.appScaffold,
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: _verdePix,
        title: const Text('Receber com qual Pix?', style: TextStyle(fontWeight: FontWeight.w900)),
        flexibleSpace: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF065F46), _verdePix, Color(0xFF14B8A6)]),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        children: [
          Text(
            'Toque na chave. A marcada com ★ PADRÃO DO APP é a que sai sozinha nas cobranças do Financeiro.',
            style: TextStyle(fontSize: 12.5, color: ctx.appTextSecondary),
          ),
          const SizedBox(height: 12),
          for (final entry in grupos.entries) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 6, top: 4),
              child: Row(children: [
                _Marca(opcao: entry.value.first, tamanho: 30),
                const SizedBox(width: 8),
                Text(entry.value.first.conta.displayName,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14.5, color: ctx.appTextPrimary)),
              ]),
            ),
            for (final o in entry.value) _linha(ctx, o),
            const SizedBox(height: 8),
          ],
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: ctx.appSurface,
            border: Border(top: BorderSide(color: _verdePix.withValues(alpha: 0.25))),
          ),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                  side: const BorderSide(color: Color(0xFF2563EB)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _salvando ? null : () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Retornar'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF16A34A),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _salvando || _sel == null ? null : () => _usar(padrao: false),
                child: const Text('Usar esta', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _salvando || _sel == null ? null : () => _usar(padrao: true),
                icon: _salvando
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.star_rounded, size: 18),
                label: const Text('Usar e deixar padrão',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _linha(BuildContext ctx, PixOpcao o) {
    final sel = _igual(o, _sel);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: sel ? _verdePix.withValues(alpha: 0.14) : ctx.appSurface,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _sel = o),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: sel ? _verdePix : ctx.appBorderSubtle, width: sel ? 2 : 1),
            ),
            child: Row(children: [
              Icon(sel ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: sel ? _verdePix : ctx.appTextMuted),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _verdePix.withValues(alpha: sel ? 1 : 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(o.tipo,
                    style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w900, color: sel ? Colors.white : _verdePix)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(o.chave,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w800, color: ctx.appTextPrimary)),
                  Wrap(spacing: 6, children: [
                    if (o.selecionadaSozinha)
                      const Text('★ PADRÃO DO APP',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: Color(0xFFD97706))),
                    if (o.padraoDaConta)
                      Text('padrão do banco', style: TextStyle(fontSize: 11, color: ctx.appTextMuted)),
                  ]),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
