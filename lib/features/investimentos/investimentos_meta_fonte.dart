// Carteira de Investimentos → progresso da Meta.
//
// Usa o ponto de extensão `GoalProgressSources` (models/financial_goal.dart):
// a aplicação ligada a uma meta (`metaId`) soma o seu valor LÍQUIDO estimado
// no progresso/«faltam» do card da meta, sem gravar depósito (as semanas do
// Projeto 52 semanas continuam vindo só dos depósitos).

import '../../models/financial_goal.dart';
import 'investimentos_calculo.dart';
import 'investimentos_repo.dart';

const String kChaveFonteInvestimentos = 'investimentos';

/// Fontes (uma por aplicação ligada à meta) com o valor líquido de hoje.
Stream<List<GoalProgressSource>> fontesDaMeta(String userDocId, String goalId) {
  final repo = InvestimentosRepo.instance;
  return repo
      .col(userDocId)
      .where('metaId', isEqualTo: goalId)
      .snapshots()
      .asyncMap((snap) async {
    final idx = await repo.indices();
    final hoje = hojeBrasilia();
    return [
      for (final d in snap.docs)
        if (d.data()['ativo'] != false)
          () {
            final inv = Investimento.fromMap(d.id, d.data());
            return GoalProgressSource(
              id: inv.id,
              label: inv.nomeExibicao,
              amount: posicao(inv, idx, hoje).liquido,
              kind: 'investimento',
            );
          }(),
    ];
  });
}

/// Registra a carteira como fonte do progresso das metas (chamar no boot).
void registrarCarteiraNasMetas() {
  GoalProgressSources.register(
    kChaveFonteInvestimentos,
    (userDocId, goalId, goalData) => fontesDaMeta(userDocId, goalId),
  );
}
