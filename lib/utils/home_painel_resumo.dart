import 'package:cloud_firestore/cloud_firestore.dart';

/// Contas puras do painel inicial (Início) — sem Firestore nem widgets, para
/// testar e para o painel não refazer conta pesada no build.

/// «Bom dia» / «Boa tarde» / «Boa noite» pela hora local.
String saudacaoPorHora(DateTime agora) {
  final h = agora.hour;
  if (h >= 5 && h < 12) return 'Bom dia';
  if (h >= 12 && h < 18) return 'Boa tarde';
  return 'Boa noite';
}

const _diasSemana = [
  'segunda-feira',
  'terça-feira',
  'quarta-feira',
  'quinta-feira',
  'sexta-feira',
  'sábado',
  'domingo',
];

const _meses = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

/// «quarta-feira, 1 de outubro de 2026» (sem depender do locale do intl).
String dataPorExtenso(DateTime d) =>
    '${_diasSemana[d.weekday - 1]}, ${d.day} de ${_meses[d.month - 1]} de ${d.year}';

/// Nome do mês em minúsculas (1 = janeiro).
String nomeDoMes(int mes) => _meses[(mes - 1).clamp(0, 11)];

DateTime? _dataDoLancamento(Map<String, dynamic> d) {
  final v = d['date'];
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  return null;
}

double _valorAbs(Map<String, dynamic> d) {
  final raw = d['amount'];
  final v = raw is num ? raw.toDouble() : (double.tryParse('$raw') ?? 0);
  return v.abs();
}

/// Resultado dos cards «Receitas/Despesas pendentes».
class PendentesResumo {
  const PendentesResumo({required this.total, required this.itens});

  static const vazio = PendentesResumo(total: 0, itens: []);

  final double total;

  /// Lançamentos (com `id`) ordenados por vencimento.
  final List<Map<String, dynamic>> itens;

  int get quantidade => itens.length;
}

/// Mesma regra das faixas de pendentes do Financeiro (`finance_screen`):
/// tira cartão de crédito (vai na fatura), respeita «mostrar fixas» e o
/// «próximos X meses», e conta de hoje até o fim do último mês incluído.
PendentesResumo resumirPendentes({
  required Iterable<({String id, Map<String, dynamic> data})> docs,
  required DateTime hoje,
  required int mesesAFrente,
  required bool mostrarFixas,
  required String campoFixa,
  Set<String> contasCartao = const {},
}) {
  final dia = DateTime(hoje.year, hoje.month, hoje.day);
  final fimExclusivo = DateTime(hoje.year, hoje.month + mesesAFrente + 1, 1);
  var total = 0.0;
  final itens = <Map<String, dynamic>>[];
  for (final doc in docs) {
    final d = Map<String, dynamic>.from(doc.data);
    d['id'] = doc.id;
    final conta = (d['financeAccountId'] ?? '').toString().trim();
    if (conta.isNotEmpty && contasCartao.contains(conta)) continue;
    if (!mostrarFixas && (d[campoFixa] ?? '').toString().isNotEmpty) continue;
    final dt = _dataDoLancamento(d);
    if (dt != null) {
      if (dt.isBefore(dia)) continue;
      if (!dt.isBefore(fimExclusivo)) continue;
    }
    total += _valorAbs(d);
    itens.add(d);
  }
  itens.sort((a, b) {
    final ta = _dataDoLancamento(a);
    final tb = _dataDoLancamento(b);
    if (ta == null || tb == null) return 0;
    return ta.compareTo(tb);
  });
  return PendentesResumo(total: total, itens: itens);
}

/// Resumo das contas fixas do mês corrente ainda em aberto (vencidas e a
/// vencer até o fim do mês). Vem dos MESMOS pendentes já escutados — nada
/// é lido a mais para montar o card.
class FixasMesResumo {
  const FixasMesResumo({
    required this.vencidas,
    required this.totalVencidas,
    required this.aVencer,
    required this.totalAVencer,
  });

  static const vazio = FixasMesResumo(
      vencidas: 0, totalVencidas: 0, aVencer: 0, totalAVencer: 0);

  final int vencidas;
  final double totalVencidas;
  final int aVencer;
  final double totalAVencer;

  int get emAberto => vencidas + aVencer;
  double get totalEmAberto => totalVencidas + totalAVencer;
}

FixasMesResumo resumirFixasDoMes({
  required Iterable<Map<String, dynamic>> pendentes,
  required DateTime hoje,
  required String campoFixa,
  Set<String> contasCartao = const {},
}) {
  final dia = DateTime(hoje.year, hoje.month, hoje.day);
  final inicioJanela = DateTime(hoje.year, hoje.month - 2, 1);
  final fimMes = DateTime(hoje.year, hoje.month + 1, 1);
  var vencidas = 0, aVencer = 0;
  var totV = 0.0, totA = 0.0;
  for (final d in pendentes) {
    if ((d[campoFixa] ?? '').toString().trim().isEmpty) continue;
    final conta = (d['financeAccountId'] ?? '').toString().trim();
    if (conta.isNotEmpty && contasCartao.contains(conta)) continue;
    final dt = _dataDoLancamento(d);
    if (dt == null) continue;
    if (dt.isBefore(inicioJanela) || !dt.isBefore(fimMes)) continue;
    final v = _valorAbs(d);
    if (v <= 0) continue;
    if (DateTime(dt.year, dt.month, dt.day).isBefore(dia)) {
      vencidas++;
      totV += v;
    } else {
      aVencer++;
      totA += v;
    }
  }
  return FixasMesResumo(
    vencidas: vencidas,
    totalVencidas: totV,
    aVencer: aVencer,
    totalAVencer: totA,
  );
}

/// Pontos da «Evolução do Saldo»: parte do saldo de abertura e soma o
/// movimento PAGO de cada dia (o mapa vem de
/// `FinanceAccountBalanceUtils.movimentoDiarioPago` — a mesma regra do saldo).
/// Dias futuros sem movimento ficam de fora (a linha para em hoje); se houver
/// pago com data futura, vai até ele — o último ponto bate com o saldo.
List<({DateTime dia, double saldo})> evolucaoDoSaldo({
  required double abertura,
  required Map<DateTime, double> movimento,
  required DateTime de,
  required DateTime ate,
  required DateTime hoje,
}) {
  final inicio = DateTime(de.year, de.month, de.day);
  var fim = DateTime(ate.year, ate.month, ate.day);
  final diaHoje = DateTime(hoje.year, hoje.month, hoje.day);
  if (fim.isAfter(diaHoje) && !inicio.isAfter(diaHoje)) {
    var ultimo = diaHoje;
    for (final k in movimento.keys) {
      final dk = DateTime(k.year, k.month, k.day);
      if (dk.isAfter(ultimo) && !dk.isAfter(fim)) ultimo = dk;
    }
    fim = ultimo;
  }
  final out = <({DateTime dia, double saldo})>[];
  var saldo = abertura;
  var atual = inicio;
  var guarda = 0;
  while (!atual.isAfter(fim) && guarda < 4000) {
    saldo += movimento[atual] ?? 0;
    out.add((dia: atual, saldo: saldo));
    atual = DateTime(atual.year, atual.month, atual.day + 1);
    guarda++;
  }
  return out;
}
