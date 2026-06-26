import '../constants/currency_formats.dart';

/// Dicas financeiras combinando **métricas do período** do usuário com **educação / mercado**
/// (lista curada, rotacionada por dia para variar sem backend).
class FinanceSmartTip {
  const FinanceSmartTip({
    required this.title,
    required this.body,
    required this.personalized,
  });

  final String title;
  final String body;
  /// `true` = baseado nos lançamentos do período; `false` = educação / contexto de mercado.
  final bool personalized;
}

/// Estatísticas agregadas do período (evita acoplar ao Firestore aqui).
class FinanceSmartTipsStats {
  const FinanceSmartTipsStats({
    required this.totalIncome,
    required this.totalExpense,
    required this.balancePeriod,
    required this.expenseTransactionCount,
    required this.incomeTransactionCount,
    required this.pendingExpenseCount,
    required this.pendingExpenseAmount,
    required this.pendingIncomeCount,
    this.topExpenseCategoryName,
    this.topExpenseCategorySharePct,
    this.fixedMonthlySum,
    this.fixedPctOfPeriodIncome,
    this.fixedIncomeMonthlySum,
    this.fixedIncomePctOfPeriodIncome,
    this.foodExpenseTotalApprox = 0,
  });

  final double totalIncome;
  final double totalExpense;
  final double balancePeriod;
  final int expenseTransactionCount;
  final int incomeTransactionCount;
  final int pendingExpenseCount;
  final double pendingExpenseAmount;
  final int pendingIncomeCount;
  final String? topExpenseCategoryName;
  final double? topExpenseCategorySharePct;
  /// Soma mensal das **despesas** fixas cadastradas (ativas).
  final double? fixedMonthlySum;
  /// `fixedMonthlySum` como % da receita do período na tela.
  final double? fixedPctOfPeriodIncome;
  /// Soma mensal das **receitas** fixas cadastradas (ativas).
  final double? fixedIncomeMonthlySum;
  /// `fixedIncomeMonthlySum` como % da receita do período na tela.
  final double? fixedIncomePctOfPeriodIncome;

  /// Heurística: soma de despesas em categorias «parecidas» com alimentação (texto da categoria).
  final double foodExpenseTotalApprox;
}

/// Dicas de mercado / educação (Brasil): atualize esta lista periodicamente em releases.
const List<({String title, String body})> kFinanceMarketEducationTips = [
  (
    title: 'Selic, CDI e reserva',
    body:
        'A taxa básica (Selic) influencia o CDI e rendimentos de CDB, poupança e Tesouro Selic. Para reserva de emergência, priorize liquidez diária e baixo risco (Tesouro Selic, CDB com liquidez).',
  ),
  (
    title: 'Bola de neve na dívida',
    body:
        'Liste dívidas do menor para o maior saldo ou do maior juro para o menor. Quite o mínimo em todas e jogue valor extra na prioridade — o efeito psicológico acelera o efeito bola de neve.',
  ),
  (
    title: 'Avalanche de juros',
    body:
        'Mate primeiro o que cobra mais juros (cartão, cheque especial). Matematicamente costuma ser o caminho mais barato; use o app para ver onde o dinheiro está indo e redirecionar parcelas.',
  ),
  (
    title: 'Metas SMART',
    body:
        'Metas específicas, mensuráveis, atingíveis, relevantes e com prazo funcionam melhor no app: ex. “Guardar R\$ 200/mês até dezembro para reserva”, em vez de “economizar mais”.',
  ),
  (
    title: 'Inflação e poder de compra',
    body:
        'Quando a inflação (IPCA) sobe, o mesmo salário compra menos. Revise assinaturas, plano de celular e mercado a cada trimestre; renegocie e use listas para cortar desperdício.',
  ),
  (
    title: 'Poupança x Tesouro Direto',
    body:
        'A poupança tem regras de rendimento fixas; em muitos cenários o Tesouro Selic ou CDB atrelado ao CDI pode render mais com risco baixo — avalie prazo e liquidez antes de mudar.',
  ),
  (
    title: 'Cartão: evite o mínimo',
    body:
        'Pagar só o mínimo do cartão prolonga juros altíssimos. Se não der para quitar tudo, negocie parcelamento ou portabilidade e congele novas compras até estabilizar.',
  ),
  (
    title: 'Automatize o bom hábito',
    body:
        'Agende transferência para poupança/investimento no dia que recebe. O que some da conta corrente antes dos gastos discricionários tende a virar patrimônio.',
  ),
  (
    title: 'Fundo de emergência',
    body:
        'Ideal: 3 a 6 meses de despesas essenciais em liquidez. Só depois aumente exposição a renda variável. Use despesas e receitas fixas cadastradas e o histórico do app como referência de mês tipo.',
  ),
  (
    title: 'Regra 50 / 30 / 20',
    body:
        'Referência clássica: cerca de 50% necessidades, 30% vida e 20% metas/poupança. Ajuste ao seu reality — o importante é ter um teto consciente para vida e não zeroar metas.',
  ),
  (
    title: '13º e extras',
    body:
        'Bônus, 13º e comissões são ótimos para abater dívida cara ou completar a reserva antes de elevar o padrão de consumo — evite gastar tudo em um único mês.',
  ),
  (
    title: 'Pequenos vazamentos',
    body:
        'Assinaturas, delivery e taxas esquecidas somam. Uma vez por mês, peça extrato e cancele o que não usa; combine um mês detox leve para resetar hábitos.',
  ),
  (
    title: 'Objetivo > exibição',
    body:
        'Carro, casa, viagem: defina valor-alvo e data no módulo de Metas e acompanhe aqui no Financeiro. Pequenos aportes mensais vencem grandes promessas sem plano.',
  ),
];

class FinanceSmartTipsComposer {
  FinanceSmartTipsComposer._();

  /// Gera até [maxTips] dicas (personalizadas primeiro, depois mercado/educação).
  static List<FinanceSmartTip> compose(FinanceSmartTipsStats s, {int maxTips = 5}) {
    final out = <FinanceSmartTip>[];
    final inc = s.totalIncome;
    final exp = s.totalExpense;
    final bal = s.balancePeriod;

    void addP(String title, String body) {
      if (out.where((t) => t.personalized && t.title == title).isNotEmpty) return;
      if (out.length >= maxTips) return;
      out.add(FinanceSmartTip(title: title, body: body, personalized: true));
    }

    if (inc < 0.01 && exp > 0.01) {
      addP(
        'Registrar receitas',
        'No período selecionado há despesas, mas pouca ou nenhuma receita. Inclua entradas reais para o app calcular percentuais, dicas sobre despesas/receitas fixas e comparativos com mais precisão.',
      );
    }

    if (bal < -0.01 && exp > 0.01) {
      addP(
        'Saldo negativo no período',
        'Despesas superam receitas neste intervalo. Abra “Onde foi o dinheiro” nas categorias no topo, corte o que for discricionário e priorize quitar dívidas com maior juro (geralmente cartão).',
      );
    }

    final topName = s.topExpenseCategoryName;
    final topPct = s.topExpenseCategorySharePct;
    if (topName != null && topPct != null && topPct >= 32 && exp > 0.01) {
      addP(
        'Concentração em "$topName"',
        'Essa categoria responde por ${topPct.toStringAsFixed(0)}% das despesas do período. Vale revisar contratos, trocar plano ou pausar gastos nessa linha até o próximo ciclo.',
      );
    }

    final fixPct = s.fixedPctOfPeriodIncome;
    if (fixPct != null && inc > 0.01 && fixPct >= 48) {
      addP(
        'Despesas fixas pesadas',
        'Suas despesas fixas cadastradas somam cerca de ${fixPct.toStringAsFixed(0)}% das receitas do período na tela. Negocie internet, escola, consórcio ou prazo — pequenas reduções liberam caixa para metas.',
      );
    }

    final fiSum = s.fixedIncomeMonthlySum;
    final fiPct = s.fixedIncomePctOfPeriodIncome;
    if (fiSum != null && fiSum > 0.01) {
      final parts = <String>[
        'Suas receitas fixas cadastradas somam ${CurrencyFormats.formatBRL(fiSum)} por mês (ex.: comissões, aluguel recebido, juros).',
      ];
      if (fiPct != null && inc > 0.01 && fiPct >= 18) {
        parts.add(
          'Isso corresponde a cerca de ${fiPct.toStringAsFixed(0)}% da receita total do período na tela — ajuda a antecipar entradas e alinhar contas a pagar.',
        );
      } else if (inc < 0.01) {
        parts.add(
          'Cadastre também as receitas do período para o app comparar fixas com o que já entrou de fato.',
        );
      }
      parts.add('Ao receber, marque as pendentes como pagas para o painel refletir o caixa real.');
      addP(
        'Receitas fixas no planejamento',
        parts.join(' '),
      );
    }

    if (s.pendingExpenseCount > 0 && s.pendingExpenseAmount > 0.01) {
      addP(
        'Contas pendentes',
        'Há ${s.pendingExpenseCount} despesa(s) pendente(s) (${CurrencyFormats.formatBRL(s.pendingExpenseAmount)} no período). Quitar evita multa/juros e deixa o painel alinhado com a realidade.',
      );
    }

    if (s.pendingIncomeCount > 0) {
      addP(
        'Receitas a receber',
        'Existem receitas pendentes no período (incluindo as geradas por receitas fixas, quando houver). Ao receber, marque como pagas para o saldo e os comparativos refletirem o caixa real.',
      );
    }

    if (inc > 0.01 && bal >= 0 && (bal / inc) >= 0.12) {
      addP(
        'Bom ritmo de caixa',
        'O saldo do período está em torno de ${((bal / inc) * 100).toStringAsFixed(0)}% da receita. Considere direcionar parte à reserva de emergência ou ao módulo Metas antes de aumentar gastos variáveis.',
      );
    }

    if (s.expenseTransactionCount > 24 && exp > inc * 1.05) {
      addP(
        'Muitos lançamentos de saída',
        'Há várias despesas no período com total acima da receita. Agrupe por categoria no preview e avalie o que pode ser antecipado, parcelado sem juros ou cortado.',
      );
    }

    final food = s.foodExpenseTotalApprox;
    if (food > 1000 && exp > 0.01) {
      final eco = food * 0.2;
      addP(
        'Economia em alimentação',
        'Pelos lançamentos do período, despesas ligadas a alimentação somam cerca de ${CurrencyFormats.formatBRL(food)}. Reduzir cerca de 20% libera ~${CurrencyFormats.formatBRL(eco)} — mercado, marmita e delivery são bons alvos.',
      );
    }

    if (inc > 0.01 && exp > inc * 0.9) {
      addP(
        'Orçamento no limite',
        'Suas despesas consomem cerca de ${((exp / inc) * 100).toStringAsFixed(0)}% da receita do período. Reserve margem para imprevistos e revise categorias variáveis.',
      );
    }

    // Mercado / educação — índices estáveis por dia (lista longa → sensação de “atualizado”).
    final daySeed = DateTime.now().toUtc().difference(DateTime.utc(2024)).inDays.abs();
    final n = kFinanceMarketEducationTips.length;
    if (n > 0 && out.length < maxTips) {
      final i0 = daySeed % n;
      var i1 = (daySeed ~/ 2 + 5) % n;
      if (i1 == i0) i1 = (i0 + 1) % n;
      for (final i in [i0, i1]) {
        if (out.length >= maxTips) break;
        final t = kFinanceMarketEducationTips[i];
        out.add(FinanceSmartTip(title: t.title, body: t.body, personalized: false));
      }
    }

    return out.take(maxTips).toList();
  }
}
