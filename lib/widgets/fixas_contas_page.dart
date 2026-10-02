import 'dart:async';

import 'package:flutter/material.dart';

import '../screens/despesas_fixas_screen.dart';
import '../screens/receitas_fixas_screen.dart';
import '../services/fixed_expense_service.dart';
import '../services/fixed_income_service.dart';
import '../theme/theme_context.dart';
import '../utils/firestore_user_doc_id.dart';
import 'finance_load_error_box.dart';
import 'fixas_a_pagar_painel.dart';
import 'fixas_mes_a_mes.dart';
import 'fixas_totalizador_card.dart';
import 'fixas_visao_geral.dart';
import 'navy_back_app_bar.dart';

const _kVermelho = Color(0xFFDC2626);
const _kVerde = Color(0xFF16A34A);

const _mesesNome = [
  'janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho',
  'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro',
];

/// «Contas fixas — <mês>» em TELA CHEIA (pedido do dono, 02/10/2026), com as
/// abas Despesas fixas / Receitas fixas no padrão gráfico do Controle Total:
/// o que pagar/receber (vencidas, 7 dias, pagas — com o botão de quitar),
/// visão geral do mês (pago × a vencer + rosca por categoria), card mês a mês
/// e o totalizador com a pizza por categoria. Antes era um bottom sheet que,
/// na Web, ficava só com o pontinho carregando.
class FixasContasPage extends StatefulWidget {
  const FixasContasPage({
    super.key,
    required this.uid,
    this.receitaInicial = false,
    this.onAbrirFinanceiro,
  });

  final String uid;
  final bool receitaInicial;

  /// Atalho opcional para o Financeiro (quando aberta pelo Início).
  final VoidCallback? onAbrirFinanceiro;

  /// Abre a página (rota normal com seta Voltar).
  static Future<void> abrir(
    BuildContext context, {
    required String uid,
    bool receita = false,
    VoidCallback? onAbrirFinanceiro,
  }) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => FixasContasPage(
          uid: uid,
          receitaInicial: receita,
          onAbrirFinanceiro: onAbrirFinanceiro,
        ),
      ),
    );
  }

  @override
  State<FixasContasPage> createState() => _FixasContasPageState();
}

class _FixasContasPageState extends State<FixasContasPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.receitaInicial ? 1 : 0,
  );

  String get _fsUid => firestoreUserDocIdForAppShell(widget.uid);

  @override
  void initState() {
    super.initState();
    _tabs.addListener(() {
      if (!_tabs.indexIsChanging && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mes = _mesesNome[DateTime.now().month - 1];
    final receita = _tabs.index == 1;
    final cor = receita ? _kVerde : _kVermelho;
    return Scaffold(
      backgroundColor: context.appScaffold,
      // Barra azul-marinho + «← Voltar» branco (antes: seta/título brancos
      // sobre fundo claro, invisíveis).
      appBar: navyBackAppBar(
        context,
        title: Text('Contas fixas — $mes',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          if (widget.onAbrirFinanceiro != null)
            IconButton(
              tooltip: 'Abrir Financeiro',
              icon: const Icon(Icons.account_balance_wallet_rounded),
              onPressed: () {
                Navigator.of(context).maybePop();
                widget.onAbrirFinanceiro!();
              },
            ),
        ],
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: cor,
          indicatorWeight: 3,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.w900),
          tabs: const [
            Tab(icon: Icon(Icons.event_note_rounded), text: 'Despesas fixas'),
            Tab(icon: Icon(Icons.savings_rounded), text: 'Receitas fixas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          _FixasAba(uid: _fsUid, receita: false),
          _FixasAba(uid: _fsUid, receita: true),
        ],
      ),
    );
  }
}

class _FixasAba extends StatefulWidget {
  const _FixasAba({required this.uid, required this.receita});

  final String uid;
  final bool receita;

  @override
  State<_FixasAba> createState() => _FixasAbaState();
}

class _FixasAbaState extends State<_FixasAba>
    with AutomaticKeepAliveClientMixin {
  Future<List<Map<String, dynamic>>>? _cadastro;
  List<Map<String, dynamic>>? _ultimoCadastro;

  /// Chave dos painéis: muda no «Tentar de novo» / ao voltar da edição para
  /// eles reabrirem as escutas.
  int _geracao = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _carregarCadastro();
  }

  void _carregarCadastro() {
    _cadastro = widget.receita
        ? FixedIncomeService().list(widget.uid)
        : FixedExpenseService().list(widget.uid);
  }

  Future<void> _gerenciar() async {
    await Navigator.of(context).push<void>(MaterialPageRoute<void>(
      builder: (_) => widget.receita
          ? ReceitasFixasScreen(uid: widget.uid)
          : DespesasFixasScreen(uid: widget.uid),
    ));
    if (!mounted) return;
    setState(() {
      _carregarCadastro();
      _geracao++;
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final cor = widget.receita ? _kVerde : _kVermelho;
    final bottom = MediaQuery.paddingOf(context).bottom;
    return RefreshIndicator(
      onRefresh: () async {
        setState(() {
          _carregarCadastro();
          _geracao++;
        });
        await _cadastro?.catchError((Object _) => const <Map<String, dynamic>>[]);
      },
      child: ListView(
        padding: EdgeInsets.only(bottom: 24 + bottom),
        children: [
          // O que pagar/receber agora (com o botão de quitar).
          FixasAPagarPainel(
            key: ValueKey('apagar-${widget.receita}-$_geracao'),
            uid: widget.uid,
            receita: widget.receita,
          ),
          FixasVisaoGeral(
            key: ValueKey('visao-${widget.receita}-$_geracao'),
            uid: widget.uid,
            receita: widget.receita,
          ),
          FixasPorMesCard(
            key: ValueKey('mes-${widget.receita}-$_geracao'),
            uid: widget.uid,
            receita: widget.receita,
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<Map<String, dynamic>>>(
            future: _cadastro,
            builder: (context, snap) {
              if (snap.hasData) _ultimoCadastro = snap.data;
              final itens = snap.data ?? _ultimoCadastro;
              if (itens == null && snap.hasError) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: FinanceLoadErrorBox(
                    error: snap.error,
                    onRetry: () => setState(_carregarCadastro),
                  ),
                );
              }
              if (itens == null) {
                return const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2.4)),
                );
              }
              if (itens.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FixasTotalizadorCard(
                  key: ValueKey('total-${widget.receita}-$_geracao'),
                  items: itens,
                  receita: widget.receita,
                  uid: widget.uid,
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: cor,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () => unawaited(_gerenciar()),
              icon: const Icon(Icons.edit_note_rounded),
              label: Text(widget.receita
                  ? 'Cadastrar e editar receitas fixas'
                  : 'Cadastrar e editar despesas fixas'),
            ),
          ),
        ],
      ),
    );
  }
}
