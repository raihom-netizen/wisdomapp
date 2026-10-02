import 'package:firebase_auth/firebase_auth.dart' as fa;
import 'package:flutter/material.dart';

import '../services/finance_sort_preference.dart';
import '../theme/theme_context.dart';
import '../utils/finance_fatura_transaction_sort.dart';

/// Seletor de ordenação compartilhado nas grids de lançamentos do Financeiro.
///
/// Botões lado a lado em vez de menu suspenso: a ordem troca num toque, e a
/// escolhida fica à vista. A escolha é GRAVADA ([FinanceSortPreference]) e
/// vale para todas as grids até o usuário mudar de novo.
class FinanceTransactionSortBar extends StatelessWidget {
  const FinanceTransactionSortBar({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
  });

  final FinanceFaturaTxSortMode value;
  final ValueChanged<FinanceFaturaTxSortMode> onChanged;
  final bool compact;

  static (IconData, String) _visual(FinanceFaturaTxSortMode m) => switch (m) {
        FinanceFaturaTxSortMode.dateAsc => (Icons.event_rounded, 'Mais antigas'),
        FinanceFaturaTxSortMode.dateDesc => (Icons.update_rounded, 'Mais recentes'),
        FinanceFaturaTxSortMode.amountDesc => (Icons.trending_up_rounded, 'Maior valor'),
        FinanceFaturaTxSortMode.amountAsc => (Icons.trending_down_rounded, 'Menor valor'),
        FinanceFaturaTxSortMode.category => (Icons.sell_rounded, 'Categoria'),
      };

  /// Ordem dos botões: as duas de data primeiro (as mais usadas), com a
  /// padrão do sistema — mais antigas — à esquerda.
  static const _ordem = [
    FinanceFaturaTxSortMode.dateAsc,
    FinanceFaturaTxSortMode.dateDesc,
    FinanceFaturaTxSortMode.amountDesc,
    FinanceFaturaTxSortMode.amountAsc,
    FinanceFaturaTxSortMode.category,
  ];

  void _escolher(FinanceFaturaTxSortMode m) {
    if (m == value) return;
    onChanged(m);
    final uid = fa.FirebaseAuth.instance.currentUser?.uid ?? '';
    FinanceSortPreference.definir(uid, m);
  }

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Icon(Icons.sort_rounded, size: 18, color: ctx.appTextMuted),
        ),
        for (final m in _ordem)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: _Botao(
              icone: _visual(m).$1,
              rotulo: _visual(m).$2,
              selecionado: m == value,
              compacto: compact,
              onTap: () => _escolher(m),
            ),
          ),
      ]),
    );
  }
}

class _Botao extends StatelessWidget {
  const _Botao({
    required this.icone,
    required this.rotulo,
    required this.selecionado,
    required this.compacto,
    required this.onTap,
  });

  final IconData icone;
  final String rotulo;
  final bool selecionado;
  final bool compacto;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ctx = context;
    final fundo = selecionado ? ctx.appNeon : ctx.appChipIdleBg;
    final texto = selecionado ? ctx.appNeonOn : ctx.appChipIdleLabel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: EdgeInsets.symmetric(horizontal: compacto ? 10 : 12, vertical: compacto ? 7 : 9),
          decoration: BoxDecoration(
            color: fundo,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: selecionado ? ctx.appNeon : ctx.appChipIdleBorder),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icone, size: compacto ? 15 : 16, color: texto),
            const SizedBox(width: 5),
            Text(
              rotulo,
              style: TextStyle(
                fontSize: compacto ? 12 : 12.5,
                fontWeight: selecionado ? FontWeight.w900 : FontWeight.w700,
                color: texto,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
