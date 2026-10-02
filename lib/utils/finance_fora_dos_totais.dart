/// Lançamentos que são dinheiro MUDANDO DE LUGAR, não receita nem despesa
/// (autorizado pelo dono em 01/10/2026: «tem que entrar só quitando os
/// lançamentos e faturas»):
///
/// - pagamento da fatura do cartão saindo da conta corrente (Pix «NU
///   PAGAMENTOS», boleto, débito automático) — `faturaPagamento`;
/// - «Pagamento recebido» no extrato do cartão — `faturaPagamento`;
/// - transferência entre contas do próprio usuário reconhecida pelo Finance
///   Pro — `transferenciaPropria` / `isTransfer`;
/// - transferência feita pelo botão «Transferência» do app (par com
///   `transferPairId`) — SÓ para quem tem Finance Pro (decisão do dono em
///   01/10/2026). Sem Finance Pro, ela continua somando como sempre.
///
/// Eles ficam de fora de TODO total de receitas/despesas do período (lista do
/// Financeiro, painel, Relatórios, gráficos de categoria, ficha da conta,
/// PDF), mas continuam no SALDO: o débito real tira da conta uma vez (e a
/// fatura é quitada pelas compras). Onde a tela calcula um saldo a partir de
/// receitas − despesas, o líquido deles volta por [financeAjusteSaldoForaDosTotais].
library;

/// Finance Pro do usuário da sessão (= tem conta ligada ao banco), resolvido
/// UMA vez por carga — pela lista de contas ([FinanceAccountsService]) ou pelo
/// detector [FixaQuitacaoService.usaFinancePro] — e lido pelas somas sem
/// nenhuma leitura extra por lançamento.
class FinanceProTotais {
  FinanceProTotais._();
  static String _uid = '';
  static bool _fp = false;

  /// Valor atual (o do último usuário registrado).
  static bool get ativo => _fp;

  /// [deServidor] false (lista do cache local) só pode LIGAR — a lista do
  /// cache pode estar incompleta e não decide um «não».
  static void registrar(String uidDoc, bool financePro, {bool deServidor = true}) {
    if (uidDoc.isEmpty) return;
    if (uidDoc != _uid) {
      _uid = uidDoc;
      _fp = financePro;
      return;
    }
    if (financePro || deServidor) _fp = financePro;
  }

  /// Só para testes.
  static void definirParaTeste(bool fp) {
    _uid = 'teste';
    _fp = fp;
  }
}

/// [financePro]: nulo = o valor resolvido da sessão ([FinanceProTotais]).
bool financeForaDosTotais(Map<String, dynamic> d, {bool? financePro}) {
  if (d['faturaPagamento'] == true || d['transferenciaPropria'] == true || d['isTransfer'] == true) {
    return true;
  }
  final fp = financePro ?? FinanceProTotais.ativo;
  return fp && (d['transferPairId'] ?? '').toString().trim().isNotEmpty;
}

/// Valor com sinal (receita +, despesa −) — para devolver ao saldo o que
/// saiu dos totais.
double financeValorComSinal(Map<String, dynamic> d) {
  final v = ((d['amount'] ?? 0) as num).toDouble().abs();
  return (d['type'] ?? 'expense').toString() == 'income' ? v : -v;
}

/// Líquido (receitas − despesas) dos lançamentos fora dos totais.
double financeAjusteSaldoForaDosTotais(Iterable<Map<String, dynamic>> docs, {bool? financePro}) {
  var s = 0.0;
  for (final d in docs) {
    if (financeForaDosTotais(d, financePro: financePro)) s += financeValorComSinal(d);
  }
  return s;
}

/// Rótulo na lista: «Pagamento de fatura · Nubank» ou «Transferência entre
/// contas». `contaDoLancamento` = nome da conta do próprio lançamento (no
/// crédito do cartão, é o cartão). Nulo = lançamento comum.
String? financeRotuloForaDosTotais(Map<String, dynamic> d, {String? contaDoLancamento, bool? financePro}) {
  if (!financeForaDosTotais(d, financePro: financePro)) return null;
  final fatura = d['faturaPagamento'] == true ||
      (d['category'] ?? '').toString().trim().toLowerCase() == 'pagamento de fatura';
  if (!fatura) return 'Transferência entre contas';
  final ehCreditoNoCartao = (d['type'] ?? 'expense').toString() == 'income';
  final cartao = ehCreditoNoCartao
      ? (contaDoLancamento ?? '').trim()
      : (d['transferCounterpartyLabel'] ?? '').toString().trim();
  return cartao.isEmpty ? 'Pagamento de fatura' : 'Pagamento de fatura · $cartao';
}
