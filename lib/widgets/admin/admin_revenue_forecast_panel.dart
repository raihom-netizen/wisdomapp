import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../theme/theme_context.dart';
import '../../utils/admin_load_guard.dart';
import 'admin_ui_kit.dart';

/// Receita prevista (só quem PAGA de verdade) vs realizada (MP no período).
///
/// 02/10/2026: antes a previsão era `totalPremiums × preço mensal` — mas quase
/// todo premium é teste/cortesia/convênio, e a previsão saía inflada. Agora
/// usa o resumo da callable `ctAdminPrevisaoReceita` (mesma da aba «Previsão &
/// planos»), carregado UMA vez no initState (nada de `.snapshots()` no build),
/// com prazo e erro visível com «Tentar de novo».
class AdminRevenueForecastPanel extends StatefulWidget {
  final double revenueRealizedMp;
  final int totalPremiums;
  final int totalUsers;
  final double pixLiquido;
  final double cardLiquido;

  const AdminRevenueForecastPanel({
    super.key,
    required this.revenueRealizedMp,
    required this.totalPremiums,
    required this.totalUsers,
    this.pixLiquido = 0,
    this.cardLiquido = 0,
  });

  @override
  State<AdminRevenueForecastPanel> createState() =>
      _AdminRevenueForecastPanelState();
}

class _AdminRevenueForecastPanelState extends State<AdminRevenueForecastPanel> {
  static const _fnNome = 'ctAdminPrevisaoReceita';
  static final _fmt = NumberFormat.currency(locale: 'pt_BR', symbol: r'R$');

  late Future<Map<String, dynamic>> _futuro;

  @override
  void initState() {
    super.initState();
    _futuro = _buscar();
  }

  Future<Map<String, dynamic>> _buscar({bool forcar = false}) async {
    try {
      final fn = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable(
        _fnNome,
        options: HttpsCallableOptions(timeout: AdminLoadGuard.callable),
      );
      final res = await AdminLoadGuard.comPrazo(
        fn.call<dynamic>({'resumo': true, 'forcar': forcar}),
        prazo: AdminLoadGuard.callable + const Duration(seconds: 10),
        oQue: 'a previsão de receita',
      );
      final data = res.data;
      if (data is! Map) throw StateError('Resposta vazia do servidor.');
      final resumo = data['resumo'];
      return resumo is Map
          ? Map<String, dynamic>.from(resumo)
          : const <String, dynamic>{};
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found' || e.code == 'unimplemented') {
        throw StateError('A função «$_fnNome» ainda não foi publicada no '
            'servidor (falta o deploy das Cloud Functions).');
      }
      rethrow;
    }
  }

  void _recarregar() {
    setState(() => _futuro = _buscar(forcar: true));
  }

  double _num(Object? v) => v is num ? v.toDouble() : 0;
  int _int(Object? v) => v is num ? v.toInt() : 0;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _futuro,
      builder: (context, snap) {
        if (snap.hasError) {
          final e = snap.error;
          if (e is FirebaseFunctionsException && e.code == 'permission-denied') {
            return _moldura(
              context,
              children: [
                _titulo(context),
                const SizedBox(height: 6),
                Text(
                  'A previsão de receita é só para admin/financeiro.',
                  style:
                      TextStyle(fontSize: 12, color: AdminUi.apoioOf(context)),
                ),
              ],
            );
          }
          return AdminErroCard(
            erro: e is StateError ? e.message : e,
            onTentar: _recarregar,
            titulo: 'Não foi possível carregar a previsão de receita',
          );
        }
        if (snap.connectionState != ConnectionState.done) {
          return _moldura(
            context,
            children: [
              _titulo(context),
              const AdminCarregando(
                  texto: 'Calculando a previsão de quem paga…'),
            ],
          );
        }
        return _conteudo(context, snap.data ?? const <String, dynamic>{});
      },
    );
  }

  Widget _moldura(BuildContext context, {required List<Widget> children}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminUi.cardOf(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AdminUi.bordaOf(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _titulo(BuildContext context, {VoidCallback? onAtualizar}) {
    return Row(
      children: [
        Icon(Icons.insights_rounded, color: Colors.indigo.shade700, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Receita prevista vs realizada (MP)',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AdminUi.tintaOf(context)),
          ),
        ),
        if (onAtualizar != null)
          IconButton(
            tooltip: 'Atualizar previsão',
            visualDensity: VisualDensity.compact,
            onPressed: onAtualizar,
            icon: const Icon(Icons.refresh_rounded, size: 20),
          ),
      ],
    );
  }

  Widget _conteudo(BuildContext context, Map<String, dynamic> r) {
    final prevista = _num(r['receitaPrevistaMes']);
    final recebidaMes = _num(r['pagoMesTotal']);
    final aReceber = _num(r['aReceberMes']);
    final pagantes = _int(r['pagantesAtivos']);
    final semPagamento =
        widget.totalPremiums > pagantes ? widget.totalPremiums - pagantes : 0;
    final extras = <String>[
      'Realizada MP no período: ${_fmt.format(widget.revenueRealizedMp)}',
      if (widget.pixLiquido > 0 || widget.cardLiquido > 0)
        'PIX líq. ${_fmt.format(widget.pixLiquido)} · '
            'Cartão líq. ${_fmt.format(widget.cardLiquido)}',
      if (_int(r['iosAtivos']) > 0)
        'iOS: ${_int(r['iosAtivos'])} ativo(s), ≈ '
            '${_fmt.format(_num(r['iosMrrEstimado']))}/mês (estimado)',
    ];

    return _moldura(
      context,
      children: [
        _titulo(context, onAtualizar: _recarregar),
        const SizedBox(height: 4),
        Text(
          'Prevista: só quem paga ($pagantes pagante(s) ativo(s) · MRR '
          '${_fmt.format(_num(r['mrr']))}). ${widget.totalPremiums} premium no '
          'cadastro — $semPagamento sem pagamento (teste/cortesia/convênio) '
          'ficam fora. Realizada: pagamentos MP no período.',
          style: TextStyle(
              fontSize: 11, color: AdminUi.apoioOf(context), height: 1.3),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, c) {
            final narrow = c.maxWidth < 400;
            final cards = [
              _metricCard(
                context,
                'Prevista no mês',
                _fmt.format(prevista),
                Icons.trending_up_rounded,
                Colors.blue.shade700,
              ),
              _metricCard(
                context,
                'Já recebida no mês',
                _fmt.format(recebidaMes),
                Icons.payments_rounded,
                Colors.green.shade700,
              ),
              _metricCard(
                context,
                'A receber até o fim do mês',
                _fmt.format(aReceber),
                Icons.hourglass_top_rounded,
                Colors.orange.shade800,
              ),
            ];
            if (narrow) {
              return Column(
                children: [
                  for (final card in cards) ...[
                    card,
                    const SizedBox(height: 8),
                  ],
                ],
              );
            }
            return Row(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  Expanded(child: cards[i]),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        Text(
          extras.join(' · '),
          style: TextStyle(
              fontSize: 12,
              color: context.isDarkMode
                  ? context.appTextSecondary
                  : Colors.grey.shade700),
        ),
      ],
    );
  }

  Widget _metricCard(BuildContext context, String title, String value,
      IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 6),
          Text(title,
              style: TextStyle(
                  fontSize: 11,
                  color: context.isDarkMode
                      ? context.appTextSecondary
                      : Colors.grey.shade700)),
          const SizedBox(height: 2),
          Text(value,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }
}
