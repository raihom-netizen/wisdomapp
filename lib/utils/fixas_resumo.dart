/// Resumo das despesas/receitas FIXAS num período — a conta por trás do
/// gráfico de «Despesas fixas» e «Receitas fixas».
///
/// Os lançamentos das fixas já nascem gerados para os próximos meses (com
/// `fixedExpenseId` / `fixedIncomeId`), então o período pode olhar para a
/// frente: o que ainda vai vencer aparece como «a pagar/receber», e o que já
/// foi como «pago/recebido». Sem Firestore aqui: recebe mapas e devolve
/// números, para o teste não precisar de banco.
library;

/// Janela escolhida no topo da tela.
///
/// `ultimos12Meses` = o mês atual e os 11 anteriores (relatório mês a mês).
enum FixasPeriodo { mesAtual, mesAnterior, tresMeses, anual, ultimos12Meses, personalizado }

/// Um lançamento de fixa, já no formato do resumo.
class FixaLinha {
  const FixaLinha({
    required this.data,
    required this.valor,
    required this.pago,
    required this.categoria,
    required this.fixaId,
    this.descricao = '',
    this.controle = false,
    this.conferidoNoBanco = false,
  });

  final DateTime data;
  final double valor;
  final bool pago;
  final String categoria;
  final String fixaId;
  final String descricao;

  /// Paga como CONTROLE (Finance Pro: `baixaSemSaldo`) — continua contando
  /// aqui, que é a «perspectiva das contas fixas»; só não entra no saldo.
  final bool controle;

  /// Conferida com um lançamento do banco (`bancoTransacaoId`) ou já é o
  /// próprio débito importado.
  final bool conferidoNoBanco;
}

/// Um mês do gráfico.
class FixaMes {
  FixaMes(this.inicio, this.pago, this.aVencer);
  final DateTime inicio;
  final double pago;
  final double aVencer;
  double get total => pago + aVencer;
}

/// Intervalo [de, ate] (ate inclusive até 23:59:59) de cada período.
///
/// «3 meses» é este + os dois próximos: fixa é compromisso que vem pela
/// frente, e é isso que se quer planejar — o que já passou está no extrato.
({DateTime de, DateTime ate}) fixasIntervalo(
  FixasPeriodo p, {
  DateTime? agora,
  DateTime? de,
  DateTime? ate,
}) {
  final hoje = agora ?? DateTime.now();
  DateTime fimDoMes(int ano, int mes) => DateTime(ano, mes + 1, 0, 23, 59, 59);
  switch (p) {
    case FixasPeriodo.mesAtual:
      return (de: DateTime(hoje.year, hoje.month, 1), ate: fimDoMes(hoje.year, hoje.month));
    case FixasPeriodo.mesAnterior:
      return (de: DateTime(hoje.year, hoje.month - 1, 1), ate: fimDoMes(hoje.year, hoje.month - 1));
    case FixasPeriodo.ultimos12Meses:
      return (de: DateTime(hoje.year, hoje.month - 11, 1), ate: fimDoMes(hoje.year, hoje.month));
    case FixasPeriodo.tresMeses:
      return (de: DateTime(hoje.year, hoje.month, 1), ate: fimDoMes(hoje.year, hoje.month + 2));
    case FixasPeriodo.anual:
      return (de: DateTime(hoje.year, 1, 1), ate: fimDoMes(hoje.year, 12));
    case FixasPeriodo.personalizado:
      final a = de ?? DateTime(hoje.year, hoje.month, 1);
      final b = ate ?? fimDoMes(hoje.year, hoje.month);
      return (
        de: DateTime(a.year, a.month, a.day),
        ate: DateTime(b.year, b.month, b.day, 23, 59, 59),
      );
  }
}

/// Converte os documentos do período nas linhas de fixa do tipo pedido.
///
/// Só entra o que tem vínculo com uma fixa — a despesa avulsa do mesmo
/// período não é fixa, e somá-la inflaria o gráfico.
List<FixaLinha> fixasDosDocs(
  Iterable<Map<String, dynamic>> docs, {
  required bool receita,
  required DateTime Function(Object? ts) data,
  bool somenteFixas = true,
  bool somentePendentes = false,
  Set<String> excluirContas = const {},
}) {
  final campo = receita ? 'fixedIncomeId' : 'fixedExpenseId';
  final tipo = receita ? 'income' : 'expense';
  final out = <FixaLinha>[];
  for (final d in docs) {
    final id = (d[campo] ?? '').toString().trim();
    if (somenteFixas && id.isEmpty) continue;
    if ((d['type'] ?? '').toString() != tipo) continue;
    if (somentePendentes && (d['status'] ?? 'paid').toString() != 'pending') continue;
    // Compra no cartão é fatura, não «conta pendente» — a mesma regra do card.
    if (excluirContas.contains((d['financeAccountId'] ?? '').toString())) continue;
    final valor = ((d['amount'] as num?) ?? 0).toDouble().abs();
    if (valor <= 0) continue;
    out.add(FixaLinha(
      data: data(d['date']),
      valor: valor,
      pago: (d['status'] ?? 'paid').toString() == 'paid',
      categoria: (d['category'] ?? '').toString().trim().isEmpty
          ? 'Outros'
          : (d['category'] as String).trim(),
      fixaId: id,
      descricao: (d['description'] ?? '').toString().trim(),
      controle: d['baixaSemSaldo'] == true,
      conferidoNoBanco: (d['bancoTransacaoId'] ?? '').toString().isNotEmpty ||
          d['source'] == 'open_finance' ||
          (d['openFinanceExternalId'] ?? '').toString().isNotEmpty,
    ));
  }
  return out;
}

/// Um bucket por mês do intervalo — inclusive os meses sem lançamento, para o
/// gráfico não «pular» um mês e parecer que ele não existe.
List<FixaMes> fixasPorMes(List<FixaLinha> linhas, DateTime de, DateTime ate) {
  final meses = <FixaMes>[];
  var cursor = DateTime(de.year, de.month, 1);
  final fim = DateTime(ate.year, ate.month, 1);
  while (!cursor.isAfter(fim)) {
    var pago = 0.0;
    var aVencer = 0.0;
    for (final l in linhas) {
      if (l.data.year != cursor.year || l.data.month != cursor.month) continue;
      if (l.pago) {
        pago += l.valor;
      } else {
        aVencer += l.valor;
      }
    }
    meses.add(FixaMes(cursor, _r(pago), _r(aVencer)));
    cursor = DateTime(cursor.year, cursor.month + 1, 1);
  }
  return meses;
}

/// Total por categoria, do maior para o menor.
List<({String categoria, double total, int quantidade})> fixasPorCategoria(
  List<FixaLinha> linhas,
) {
  final m = <String, ({double total, int quantidade})>{};
  for (final l in linhas) {
    final a = m[l.categoria] ?? (total: 0.0, quantidade: 0);
    m[l.categoria] = (total: a.total + l.valor, quantidade: a.quantidade + 1);
  }
  final out = m.entries
      .map((e) => (categoria: e.key, total: _r(e.value.total), quantidade: e.value.quantidade))
      .toList()
    ..sort((a, b) => b.total.compareTo(a.total));
  return out;
}

/// Números do relatório «mês a mês»: total, média por mês, o mês mais caro e
/// a variação de cada mês contra o anterior (null quando o anterior é zero —
/// não há percentual honesto sobre zero). Só soma o que [fixasPorMes] já deu.
class FixasEstatisticas {
  FixasEstatisticas._(this.total, this.media, this.maior, this.variacoes);

  factory FixasEstatisticas.de(List<FixaMes> meses) {
    final total = meses.fold<double>(0, (a, m) => a + m.total);
    FixaMes? maior;
    for (final m in meses) {
      if (m.total > 0 && (maior == null || m.total > maior.total)) maior = m;
    }
    final variacoes = <double?>[];
    for (var i = 0; i < meses.length; i++) {
      if (i == 0 || meses[i - 1].total <= 0) {
        variacoes.add(null);
      } else {
        variacoes.add((meses[i].total - meses[i - 1].total) / meses[i - 1].total * 100);
      }
    }
    return FixasEstatisticas._(
      _r(total),
      meses.isEmpty ? 0 : _r(total / meses.length),
      maior,
      variacoes,
    );
  }

  final double total;

  /// Média por mês do intervalo (meses zerados contam: é «quanto por mês»).
  final double media;
  final FixaMes? maior;

  /// Mesmo índice de `meses`: % contra o mês anterior.
  final List<double?> variacoes;
}

double _r(double v) => (v * 100).roundToDouble() / 100;

/// Valor curto para o rótulo em cima da barra (ex.: «2,1 mil», «850»).
String valorCompactoBarra(double v) {
  if (v <= 0) return '';
  if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1).replaceAll('.', ',')} mi';
  if (v >= 1000) return '${(v / 1000).toStringAsFixed(1).replaceAll('.', ',')} mil';
  return v.toStringAsFixed(0);
}
