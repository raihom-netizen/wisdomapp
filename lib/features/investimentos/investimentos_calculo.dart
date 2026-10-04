// Carteira de Investimentos — cálculo PURO (sem Firestore), espelho de
// `functions/investimentos_calculo.js`. Mudou aqui, muda lá (e nos dois testes:
// `test/investimentos_calculo_test.dart` e `functions/teste_investimentos_calculo.js`).
//
// São ESTIMATIVAS com as taxas oficiais do Banco Central (SGS): o banco pode
// arredondar dia a dia de outro jeito e o valor dele variar alguns centavos.
//
// Convenções:
//  - Datas em texto «aaaa-mm-dd» (dia civil de Brasília), sem fuso.
//  - Juros de um dia útil D entram no valor a partir de D+1: a posição na data X
//    soma os dias úteis do intervalo [início, X).
//  - Aplicação = lote (data, principal). Resgate consome do lote MAIS ANTIGO
//    (FIFO), para o IR regressivo de cada lote ficar certo.
//  - Resgate é o valor LÍQUIDO que caiu na conta (é o que o banco mostra).

import 'dart:math' as math;

// ── Datas ──────────────────────────────────────────────────────────────────

String isoDe(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime? parseIso(String? s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s ?? '');
  if (m == null) return null;
  return DateTime.utc(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
}

String addDias(String s, int n) {
  final d = parseIso(s)!;
  return isoDe(DateTime.utc(d.year, d.month, d.day + n));
}

/// Soma meses mantendo o dia (31/01 + 1 mês = 28 ou 29/02, como os bancos).
String addMeses(String s, int n) {
  final d = parseIso(s)!;
  final alvo = d.month - 1 + n;
  final ano = d.year + (alvo / 12).floor();
  final mes = ((alvo % 12) + 12) % 12 + 1;
  final ultimo = DateTime.utc(ano, mes + 1, 0).day;
  return isoDe(DateTime.utc(ano, mes, math.min(d.day, ultimo)));
}

int diasCorridos(String a, String b) => (parseIso(b)!.difference(parseIso(a)!).inHours / 24).round();

String mesDe(String s) => s.substring(0, 7);
String primeiroDoMes(String s) => '${mesDe(s)}-01';

/// Hoje (Brasília, UTC−3) em aaaa-mm-dd.
String hojeBrasilia([DateTime? agora]) =>
    isoDe((agora ?? DateTime.now()).toUtc().subtract(const Duration(hours: 3)));

/// Domingo de Páscoa (Meeus/Jones/Butcher).
String pascoa(int ano) {
  final a = ano % 19, b = ano ~/ 100, c = ano % 100, d = b ~/ 4, e = b % 4;
  final f = (b + 8) ~/ 25, g = (b - f + 1) ~/ 3;
  final h = (19 * a + b - d - g + 15) % 30;
  final i = c ~/ 4, k = c % 4;
  final l = (32 + 2 * e + 2 * i - h - k) % 7;
  final m = (a + 11 * h + 22 * l) ~/ 451;
  final mes = (h + l - 7 * m + 114) ~/ 31;
  final dia = ((h + l - 7 * m + 114) % 31) + 1;
  return isoDe(DateTime.utc(ano, mes, dia));
}

final Map<int, Set<String>> _feriadosCache = {};

/// Feriados nacionais (calendário ANBIMA).
Set<String> feriadosDoAno(int ano) {
  return _feriadosCache.putIfAbsent(ano, () {
    final p = pascoa(ano);
    final fixos = ['01-01', '04-21', '05-01', '09-07', '10-12', '11-02', '11-15', '12-25'];
    if (ano >= 2024) fixos.add('11-20'); // Lei 14.759/2023
    final set = fixos.map((x) => '$ano-$x').toSet();
    set
      ..add(addDias(p, -48))
      ..add(addDias(p, -47))
      ..add(addDias(p, -2))
      ..add(addDias(p, 60));
    return set;
  });
}

bool ehDiaUtilCalendario(String s) {
  final d = parseIso(s)!;
  if (d.weekday == DateTime.saturday || d.weekday == DateTime.sunday) return false;
  return !feriadosDoAno(d.year).contains(s);
}

// ── Índices (indices_bcb/{serie}) ──────────────────────────────────────────

class SeriesBcb {
  static const cdi = 12;
  static const selic = 11;
  static const ipca = 433;
  static const tr = 226;
  static const poupanca = 195;
  static const metaSelic = 432;
  static const todas = [cdi, selic, ipca, tr, poupanca, metaSelic];
}

class SerieOrdenada {
  SerieOrdenada(this.mapa) : chaves = (mapa.keys.toList()..sort());
  final Map<String, double> mapa;
  final List<String> chaves;
  String get primeira => chaves.isEmpty ? '' : chaves.first;
  String get ultima => chaves.isEmpty ? '' : chaves.last;
  bool get vazia => chaves.isEmpty;

  /// Último valor com chave <= k; sem nenhum, o primeiro.
  double? valorAte(String k) {
    if (chaves.isEmpty) return null;
    var lo = 0, hi = chaves.length - 1, achou = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (chaves[mid].compareTo(k) <= 0) {
        achou = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return mapa[chaves[achou >= 0 ? achou : 0]];
  }
}

/// `{aaaa-mm: {dd: valor}}` do doc → {aaaa-mm-dd: valor}.
Map<String, double> mapaDiario(Map<String, dynamic>? doc) {
  final out = <String, double>{};
  final meses = (doc?['meses'] as Map?) ?? const {};
  final ks = meses.keys.map((e) => e.toString()).toList()..sort();
  for (final mes in ks) {
    final dias = (meses[mes] as Map?) ?? const {};
    final ds = dias.keys.map((e) => e.toString()).toList()..sort();
    for (final dia in ds) {
      final v = dias[dia];
      final n = v is num ? v.toDouble() : double.tryParse(v.toString());
      if (n != null && n.isFinite) out['$mes-$dia'] = n;
    }
  }
  return out;
}

class IndicesBcb {
  IndicesBcb({
    required this.cdi,
    required this.selic,
    required this.ipca,
    required this.tr,
    required this.poupanca,
    required this.metaSelic,
  });

  final SerieOrdenada cdi, selic, ipca, tr, poupanca, metaSelic;

  /// `docs` = {12: doc, 11: doc, …} (dados de indices_bcb/{serie}).
  factory IndicesBcb.deDocs(Map<int, Map<String, dynamic>?> docs) {
    final ipcaMensal = <String, double>{};
    mapaDiario(docs[SeriesBcb.ipca]).forEach((k, v) => ipcaMensal[k.substring(0, 7)] = v);
    return IndicesBcb(
      cdi: SerieOrdenada(mapaDiario(docs[SeriesBcb.cdi])),
      selic: SerieOrdenada(mapaDiario(docs[SeriesBcb.selic])),
      ipca: SerieOrdenada(ipcaMensal),
      tr: SerieOrdenada(mapaDiario(docs[SeriesBcb.tr])),
      poupanca: SerieOrdenada(mapaDiario(docs[SeriesBcb.poupanca])),
      metaSelic: SerieOrdenada(mapaDiario(docs[SeriesBcb.metaSelic])),
    );
  }

  factory IndicesBcb.vazio() => IndicesBcb.deDocs(const {});

  /// Data do último CDI publicado (para mostrar «taxas até dd/mm»).
  String get ultimaAtualizacao => cdi.ultima;
}

/// Dia útil: dentro do período publicado do CDI vale a série; fora, o calendário.
bool ehDiaUtil(String s, IndicesBcb? idx) {
  final serie = idx?.cdi;
  if (serie != null && !serie.vazia && s.compareTo(serie.primeira) >= 0 && s.compareTo(serie.ultima) <= 0) {
    return serie.mapa.containsKey(s);
  }
  return ehDiaUtilCalendario(s);
}

/// Dias úteis em [a, b).
int diasUteis(String a, String b, IndicesBcb? idx) {
  var n = 0;
  for (var s = a; s.compareTo(b) < 0; s = addDias(s, 1)) {
    if (ehDiaUtil(s, idx)) n++;
  }
  return n;
}

double _taxaDoDia(SerieOrdenada? serie, String s) {
  if (serie == null || serie.vazia) return 0;
  return serie.mapa[s] ?? serie.valorAte(s) ?? 0;
}

// ── Impostos ───────────────────────────────────────────────────────────────

/// IR regressivo da renda fixa por dias corridos (Lei 11.033/2004).
double irAliquota(int dias) {
  if (dias <= 180) return 22.5;
  if (dias <= 360) return 20;
  if (dias <= 720) return 17.5;
  return 15;
}

/// IOF regressivo (Decreto 6.306/2007, anexo): % do rendimento por dias corridos.
const List<int> kTabelaIof = [
  100, 96, 93, 90, 86, 83, 80, 76, 73, 70, 66, 63, 60, 56, 53, 50, //
  46, 43, 40, 36, 33, 30, 26, 23, 20, 16, 13, 10, 6, 3, 0,
];

double iofAliquota(int dias) {
  if (dias >= 30) return 0;
  if (dias < 0) return 100;
  return kTabelaIof[dias].toDouble();
}

int? proximaFaixaIr(int dias) {
  for (final limite in const [181, 361, 721]) {
    if (dias < limite) return limite;
  }
  return null;
}

// ── Tipos ──────────────────────────────────────────────────────────────────

class TipoInvestimento {
  const TipoInvestimento(this.id, this.rotulo, this.indexador,
      {this.isentoIR = false, this.isentoIOF = false, this.semImposto = false});
  final String id, rotulo, indexador;
  final bool isentoIR, isentoIOF, semImposto;
}

const List<TipoInvestimento> kTiposInvestimento = [
  TipoInvestimento('cdb', 'CDB', 'cdi'),
  TipoInvestimento('lci', 'LCI', 'cdi', isentoIR: true),
  TipoInvestimento('lca', 'LCA', 'cdi', isentoIR: true),
  TipoInvestimento('lc', 'LC', 'cdi'),
  TipoInvestimento('caixinha', 'Caixinha / cofrinho', 'cdi'),
  TipoInvestimento('tesouro_selic', 'Tesouro Selic', 'selic'),
  TipoInvestimento('tesouro_prefixado', 'Tesouro Prefixado', 'pre'),
  TipoInvestimento('tesouro_ipca', 'Tesouro IPCA+', 'ipca'),
  TipoInvestimento('poupanca', 'Poupança', 'poupanca', isentoIR: true, isentoIOF: true),
  TipoInvestimento('previdencia', 'Previdência', 'manual', isentoIR: true, isentoIOF: true, semImposto: true),
  TipoInvestimento('fundo', 'Fundo', 'manual', isentoIR: true, isentoIOF: true, semImposto: true),
  TipoInvestimento('acoes', 'Ações', 'manual', isentoIR: true, isentoIOF: true, semImposto: true),
  TipoInvestimento('fii', 'FII', 'manual', isentoIR: true, isentoIOF: true, semImposto: true),
  TipoInvestimento('outro', 'Outro', 'manual', isentoIR: true, isentoIOF: true, semImposto: true),
];

const List<String> kIndexadores = ['cdi', 'selic', 'pre', 'ipca', 'poupanca', 'manual'];

TipoInvestimento infoTipo(String? tipo) =>
    kTiposInvestimento.firstWhere((t) => t.id == tipo, orElse: () => kTiposInvestimento.last);

// ── Modelo ─────────────────────────────────────────────────────────────────

class MovimentoInvestimento {
  const MovimentoInvestimento({
    required this.id,
    required this.tipo,
    required this.data,
    required this.valor,
    this.transacoes = const [],
    this.origem = '',
  });
  final String id;

  /// 'aporte' | 'resgate'
  final String tipo;
  final String data;
  final double valor;
  final List<String> transacoes;
  final String origem;

  bool get resgate => tipo == 'resgate';

  factory MovimentoInvestimento.fromMap(Map m) => MovimentoInvestimento(
        id: (m['id'] ?? '').toString(),
        tipo: (m['tipo'] ?? 'aporte').toString(),
        data: (m['data'] ?? '').toString(),
        valor: (m['valor'] is num) ? (m['valor'] as num).toDouble() : double.tryParse('${m['valor']}') ?? 0,
        transacoes: ((m['transacoes'] as List?) ?? const []).map((e) => e.toString()).toList(),
        origem: (m['origem'] ?? '').toString(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'tipo': tipo,
        'data': data,
        'valor': valor,
        'transacoes': transacoes,
        if (origem.isNotEmpty) 'origem': origem,
      };
}

class Investimento {
  const Investimento({
    this.id = '',
    this.nome = '',
    this.tipo = 'cdb',
    this.indexadorGravado = '',
    this.taxa = 0,
    this.banco = '',
    this.contaId = '',
    this.contaNome = '',
    this.vencimento = '',
    this.liquidezDiaria = false,
    this.valorAtual = 0,
    this.valorAtualEm = '',
    this.metaId = '',
    this.ativo = true,
    this.avisos = true,
    this.isentoIRGravado,
    this.movimentos = const [],
  });

  final String id, nome, tipo, indexadorGravado, banco, contaId, contaNome, vencimento, metaId, valorAtualEm;
  final double taxa, valorAtual;
  final bool liquidezDiaria, ativo, avisos;
  final bool? isentoIRGravado;
  final List<MovimentoInvestimento> movimentos;

  String get indexador => kIndexadores.contains(indexadorGravado) ? indexadorGravado : infoTipo(tipo).indexador;
  bool get isentoIR => isentoIRGravado ?? infoTipo(tipo).isentoIR;
  bool get isentoIOF => infoTipo(tipo).isentoIOF;
  bool get manual => indexador == 'manual';
  String get nomeExibicao => nome.trim().isNotEmpty ? nome : infoTipo(tipo).rotulo;

  factory Investimento.fromMap(String id, Map<String, dynamic> m) {
    double n(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}') ?? 0;
    return Investimento(
      id: id,
      nome: (m['nome'] ?? '').toString(),
      tipo: (m['tipo'] ?? 'cdb').toString(),
      indexadorGravado: (m['indexador'] ?? '').toString(),
      taxa: n(m['taxa']),
      banco: (m['banco'] ?? '').toString(),
      contaId: (m['contaId'] ?? '').toString(),
      contaNome: (m['contaNome'] ?? '').toString(),
      vencimento: (m['vencimento'] ?? '').toString(),
      liquidezDiaria: m['liquidezDiaria'] == true,
      valorAtual: n(m['valorAtual']),
      valorAtualEm: (m['valorAtualEm'] ?? '').toString(),
      metaId: (m['metaId'] ?? '').toString(),
      ativo: m['ativo'] != false,
      avisos: m['avisos'] != false,
      isentoIRGravado: m['isentoIR'] is bool ? m['isentoIR'] as bool : null,
      movimentos: ((m['movimentos'] as List?) ?? const [])
          .whereType<Map>()
          .map(MovimentoInvestimento.fromMap)
          .toList(),
    );
  }

  /// Campos de cadastro (sem movimentos — esses vão por arrayUnion).
  Map<String, dynamic> cadastroMap() => {
        'nome': nome,
        'tipo': tipo,
        'indexador': indexador,
        'taxa': taxa,
        'banco': banco,
        'contaId': contaId,
        'contaNome': contaNome,
        'vencimento': vencimento,
        'liquidezDiaria': liquidezDiaria,
        'valorAtual': valorAtual,
        'valorAtualEm': valorAtualEm,
        'metaId': metaId,
        'ativo': ativo,
        'avisos': avisos,
      };

  Investimento copyWith({
    String? id,
    String? nome,
    String? tipo,
    String? indexador,
    double? taxa,
    String? banco,
    String? contaId,
    String? contaNome,
    String? vencimento,
    bool? liquidezDiaria,
    double? valorAtual,
    String? valorAtualEm,
    String? metaId,
    bool? ativo,
    bool? avisos,
    bool? isentoIR,
    List<MovimentoInvestimento>? movimentos,
  }) =>
      Investimento(
        id: id ?? this.id,
        nome: nome ?? this.nome,
        tipo: tipo ?? this.tipo,
        indexadorGravado: indexador ?? indexadorGravado,
        taxa: taxa ?? this.taxa,
        banco: banco ?? this.banco,
        contaId: contaId ?? this.contaId,
        contaNome: contaNome ?? this.contaNome,
        vencimento: vencimento ?? this.vencimento,
        liquidezDiaria: liquidezDiaria ?? this.liquidezDiaria,
        valorAtual: valorAtual ?? this.valorAtual,
        valorAtualEm: valorAtualEm ?? this.valorAtualEm,
        metaId: metaId ?? this.metaId,
        ativo: ativo ?? this.ativo,
        avisos: avisos ?? this.avisos,
        isentoIRGravado: isentoIR ?? isentoIRGravado,
        movimentos: movimentos ?? this.movimentos,
      );
}

String _fmtPct(double v) {
  final s = v.toStringAsFixed(2).replaceAll('.', ',');
  return s.endsWith(',00') ? s.substring(0, s.length - 3) : s;
}

/// «110% do CDI», «IPCA + 6,50%», «12,50% a.a.», «Selic», «Poupança».
String rotuloTaxa(Investimento inv) {
  final t = inv.taxa;
  switch (inv.indexador) {
    case 'cdi':
      return '${_fmtPct(t == 0 ? 100 : t)}% do CDI';
    case 'selic':
      return t != 0 ? 'Selic + ${_fmtPct(t)}%' : 'Selic';
    case 'pre':
      return '${_fmtPct(t)}% a.a.';
    case 'ipca':
      return 'IPCA + ${_fmtPct(t)}%';
    case 'poupanca':
      return 'Poupança';
    default:
      return 'Valor informado';
  }
}

// ── Poupança ───────────────────────────────────────────────────────────────

/// Rendimento de UM mês da poupança (Lei 12.703/2012), em %: meta Selic > 8,5%
/// a.a. → 0,5% a.m. + TR; senão 70% da meta Selic mensalizada + TR.
double poupancaMensal(double metaSelicAA, double trPct) {
  final juros = metaSelicAA > 8.5 ? 0.5 : (math.pow(1 + 0.7 * metaSelicAA / 100, 1 / 12) - 1) * 100;
  return ((1 + juros / 100) * (1 + trPct / 100) - 1) * 100;
}

double taxaPoupancaEm(String s, IndicesBcb? idx) {
  final oficial = idx?.poupanca.mapa[s];
  if (oficial != null) return oficial;
  final meta = idx?.metaSelic.valorAte(s);
  final tr = idx?.tr.mapa[s];
  return poupancaMensal(meta ?? 10, tr ?? 0);
}

/// Depósito em 29, 30 ou 31 rende a partir do dia 1º seguinte.
String inicioPoupanca(String s) {
  final d = parseIso(s)!;
  if (d.day <= 28) return s;
  return isoDe(DateTime.utc(d.year, d.month + 1, 1));
}

// ── Fator ──────────────────────────────────────────────────────────────────

/// Fator de [inicio, fim) para 1 real aplicado em `inicio` (ver o .js).
double fator(String indexador, double taxa, String inicio, String fim, IndicesBcb? idx) {
  if (inicio.isEmpty || fim.isEmpty || fim.compareTo(inicio) <= 0) return 1;
  switch (indexador) {
    case 'cdi':
      final p = (taxa == 0 ? 100 : taxa) / 100;
      var f = 1.0;
      for (var s = inicio; s.compareTo(fim) < 0; s = addDias(s, 1)) {
        if (!ehDiaUtil(s, idx)) continue;
        f *= 1 + (_taxaDoDia(idx?.cdi, s) / 100) * p;
      }
      return f;
    case 'selic':
      var f = 1.0;
      var du = 0;
      for (var s = inicio; s.compareTo(fim) < 0; s = addDias(s, 1)) {
        if (!ehDiaUtil(s, idx)) continue;
        du++;
        f *= 1 + _taxaDoDia(idx?.selic, s) / 100;
      }
      return f * math.pow(1 + taxa / 100, du / 252);
    case 'pre':
      return math.pow(1 + taxa / 100, diasUteis(inicio, fim, idx) / 252).toDouble();
    case 'ipca':
      var f = 1.0;
      var duTotal = 0;
      var mes = primeiroDoMes(inicio);
      while (mes.compareTo(fim) < 0) {
        final prox = addMeses(mes, 1);
        final a = inicio.compareTo(mes) > 0 ? inicio : mes;
        final b = fim.compareTo(prox) < 0 ? fim : prox;
        final duNo = diasUteis(a, b, idx);
        var duMes = diasUteis(mes, prox, idx);
        if (duMes == 0) duMes = 1;
        duTotal += duNo;
        final ipcaMes = idx?.ipca.valorAte(mesDe(mes)) ?? 0;
        f *= math.pow(1 + ipcaMes / 100, duNo / duMes);
        mes = prox;
      }
      return f * math.pow(1 + taxa / 100, duTotal / 252);
    case 'poupanca':
      final ini = inicioPoupanca(inicio);
      var f = 1.0;
      for (var k = 0;; k++) {
        final s = addMeses(ini, k);
        final prox = addMeses(ini, k + 1);
        if (prox.compareTo(fim) > 0) break;
        f *= 1 + taxaPoupancaEm(s, idx) / 100;
      }
      return f;
    default:
      return 1;
  }
}

// ── Lotes, FIFO e posição ──────────────────────────────────────────────────

class LoteInvestimento {
  LoteInvestimento({required this.id, required this.data, required this.principal, this.porReal = 1});
  final String id, data;
  double principal;

  /// Bruto por real de principal (simulação de resgate).
  double porReal;
}

class LotePosicao {
  const LotePosicao({
    required this.id,
    required this.data,
    required this.principal,
    required this.bruto,
    required this.iof,
    required this.ir,
    required this.dias,
  });
  final String id, data;
  final double principal, bruto, iof, ir;
  final int dias;
}

class ResultadoResgate {
  ResultadoResgate({required this.liquido});
  final double liquido;
  String id = '', data = '';
  double principal = 0, rendimento = 0, iof = 0, ir = 0, excedente = 0;

  /// Rendimento LÍQUIDO que chegou = valor − principal devolvido.
  double get rendimentoLiquido => math.max(0, liquido - principal);
}

class PosicaoInvestimento {
  PosicaoInvestimento(this.data);
  final String data;
  double bruto = 0, investido = 0, iof = 0, ir = 0;
  final List<LotePosicao> lotes = [];
  final List<ResultadoResgate> resgates = [];
  double get rendimento => bruto - investido;
  double get liquido => bruto - iof - ir;
}

List<MovimentoInvestimento> movimentosOrdenados(Investimento inv) {
  final lista = <(int, MovimentoInvestimento)>[];
  for (var i = 0; i < inv.movimentos.length; i++) {
    final m = inv.movimentos[i];
    if (parseIso(m.data) != null && m.valor > 0) lista.add((i, m));
  }
  lista.sort((a, b) {
    final c = a.$2.data.compareTo(b.$2.data);
    if (c != 0) return c;
    final r = (a.$2.resgate ? 1 : 0) - (b.$2.resgate ? 1 : 0);
    return r != 0 ? r : a.$1 - b.$1;
  });
  return lista.map((e) => e.$2).toList();
}

({double rend, double iof, double ir, int dias}) _impostos(Investimento inv, String loteData, double principal, double bruto, String data) {
  final rend = bruto - principal;
  final dias = diasCorridos(loteData, data);
  if (rend <= 0) return (rend: rend, iof: 0, ir: 0, dias: dias);
  final iof = inv.isentoIOF ? 0.0 : rend * iofAliquota(dias) / 100;
  final ir = inv.isentoIR ? 0.0 : (rend - iof) * irAliquota(dias) / 100;
  return (rend: rend, iof: iof, ir: ir, dias: dias);
}

ResultadoResgate _consumirFifo(Investimento inv, List<LoteInvestimento> lotes, String data, double liquido,
    double Function(LoteInvestimento) brutoDoLote) {
  var falta = liquido;
  final out = ResultadoResgate(liquido: liquido);
  for (final lote in lotes) {
    if (falta <= 0.000001) break;
    if (lote.principal <= 0.000001) continue;
    final bruto = brutoDoLote(lote);
    final imp = _impostos(inv, lote.data, lote.principal, bruto, data);
    final liqLote = bruto - imp.iof - imp.ir;
    if (liqLote <= 0.000001) continue;
    final pega = math.min(falta, liqLote);
    final frac = pega / liqLote;
    out.principal += lote.principal * frac;
    out.rendimento += imp.rend * frac;
    out.iof += imp.iof * frac;
    out.ir += imp.ir * frac;
    lote.principal -= lote.principal * frac;
    falta -= pega;
  }
  if (falta > 0.005) out.excedente = falta;
  return out;
}

/// Posição na `data` (movimentos até essa data). Valor manual: o último valor
/// informado (`valorAtual`), repartido entre os lotes pelo principal.
PosicaoInvestimento posicao(Investimento inv, IndicesBcb? idx, String data) {
  final ix = inv.indexador;
  final lotes = <LoteInvestimento>[];
  final out = PosicaoInvestimento(data);
  for (final m in movimentosOrdenados(inv)) {
    if (m.data.compareTo(data) > 0) break;
    if (m.resgate) {
      final r = _consumirFifo(inv, lotes, m.data, m.valor,
          inv.manual ? (l) => l.principal : (l) => l.principal * fator(ix, inv.taxa, l.data, m.data, idx));
      r
        ..id = m.id
        ..data = m.data;
      out.resgates.add(r);
    } else {
      lotes.add(LoteInvestimento(id: m.id, data: m.data, principal: m.valor));
    }
  }
  final vivos = lotes.where((l) => l.principal > 0.000001).toList();
  out.investido = vivos.fold(0.0, (a, l) => a + l.principal);
  for (final l in vivos) {
    final bruto = inv.manual
        ? (inv.valorAtual > 0 && out.investido > 0 ? inv.valorAtual * l.principal / out.investido : l.principal)
        : l.principal * fator(ix, inv.taxa, l.data, data, idx);
    final imp = inv.manual
        ? (rend: bruto - l.principal, iof: 0.0, ir: 0.0, dias: diasCorridos(l.data, data))
        : _impostos(inv, l.data, l.principal, bruto, data);
    out.bruto += bruto;
    out.iof += imp.iof;
    out.ir += imp.ir;
    out.lotes.add(LotePosicao(id: l.id, data: l.data, principal: l.principal, bruto: bruto, iof: imp.iof, ir: imp.ir, dias: imp.dias));
  }
  return out;
}

({double aportes, double resgates}) fluxoEntre(Investimento inv, String a, String b) {
  var ap = 0.0, rs = 0.0;
  for (final m in movimentosOrdenados(inv)) {
    if (m.data.compareTo(a) <= 0 || m.data.compareTo(b) > 0) continue;
    if (m.resgate) {
      rs += m.valor;
    } else {
      ap += m.valor;
    }
  }
  return (aportes: ap, resgates: rs);
}

/// Rendimento BRUTO entre as posições a e b, descontando aplicações e resgates.
double? rendimentoEntre(Investimento inv, IndicesBcb? idx, String a, String b) {
  if (inv.manual) return null;
  final pa = posicao(inv, idx, a);
  final pb = posicao(inv, idx, b);
  final f = fluxoEntre(inv, a, b);
  final retidos = pb.resgates
      .where((r) => r.data.compareTo(a) > 0 && r.data.compareTo(b) <= 0)
      .fold(0.0, (s, r) => s + r.iof + r.ir);
  return pb.bruto - pa.bruto - f.aportes + f.resgates + retidos;
}

String diaUtilAnterior(String s, IndicesBcb? idx) {
  var d = addDias(s, -1);
  for (var i = 0; i < 15 && !ehDiaUtil(d, idx); i++) {
    d = addDias(d, -1);
  }
  return d;
}

class MarcoImposto {
  const MarcoImposto(this.tipo, this.lote, this.data, [this.aliquota]);

  /// 'iof_zero' | 'ir_faixa'
  final String tipo, lote, data;
  final double? aliquota;
}

class ResumoInvestimento {
  ResumoInvestimento(this.posicao, this.rendDia, this.rendMes, this.rendAcumulado, this.marcos);
  final PosicaoInvestimento posicao;
  final double? rendDia, rendMes;
  final double rendAcumulado;
  final List<MarcoImposto> marcos;
}

List<MarcoImposto> marcosDeImposto(Investimento inv, PosicaoInvestimento pos, String hoje) {
  final out = <MarcoImposto>[];
  for (final l in pos.lotes) {
    if (!inv.isentoIOF && l.dias < 30) out.add(MarcoImposto('iof_zero', l.id, addDias(l.data, 30)));
    if (!inv.isentoIR) {
      final prox = proximaFaixaIr(l.dias);
      if (prox != null) out.add(MarcoImposto('ir_faixa', l.id, addDias(l.data, prox), irAliquota(prox)));
    }
  }
  return out.where((m) => m.data.compareTo(hoje) >= 0).toList()..sort((a, b) => a.data.compareTo(b.data));
}

ResumoInvestimento resumo(Investimento inv, IndicesBcb? idx, String hoje) {
  final pos = posicao(inv, idx, hoje);
  final rendDia = inv.manual ? null : rendimentoEntre(inv, idx, diaUtilAnterior(hoje, idx), hoje);
  final rendMes = rendimentoEntre(inv, idx, primeiroDoMes(hoje), hoje);
  final realizado = pos.resgates.fold(0.0, (s, r) => s + r.rendimento);
  return ResumoInvestimento(pos, rendDia, rendMes, pos.rendimento + realizado, marcosDeImposto(inv, pos, hoje));
}

/// Resgate simulado: quanto do valor LÍQUIDO é principal e quanto é rendimento.
ResultadoResgate simularResgate(Investimento inv, IndicesBcb? idx, String data, double liquido, {bool tudo = false}) {
  final pos = posicao(inv, idx, data);
  final valor = tudo ? pos.liquido : liquido;
  final lotes = pos.lotes
      .map((l) => LoteInvestimento(id: l.id, data: l.data, principal: l.principal, porReal: l.principal > 0 ? l.bruto / l.principal : 1))
      .toList();
  return _consumirFifo(inv, lotes, data, valor, (l) => l.principal * l.porReal);
}

/// Rentabilidade do mês (%) de 1 real aplicado no dia 1º, com o IR da faixa.
double? taxaMesLiquida(Investimento inv, IndicesBcb? idx, String mesIso, int diasDoLoteMaisAntigo) {
  if (inv.manual || inv.indexador == 'poupanca') return null;
  final ini = primeiroDoMes(mesIso);
  final bruto = (fator(inv.indexador, inv.taxa, ini, addMeses(ini, 1), idx) - 1) * 100;
  if (inv.isentoIR) return bruto;
  return bruto * (1 - irAliquota(diasDoLoteMaisAntigo) / 100);
}

double taxaPoupancaMes(IndicesBcb? idx, String mesIso) => taxaPoupancaEm(primeiroDoMes(mesIso), idx);

/// Mesmos movimentos simulados em outro indexador (comparação com CDI/poupança).
Investimento comoSeFosse(Investimento inv, String indexador, double taxa) => inv.copyWith(
      tipo: indexador == 'poupanca' ? 'poupanca' : 'cdb',
      indexador: indexador,
      taxa: taxa,
      isentoIR: indexador == 'poupanca',
    );

class PontoEvolucao {
  const PontoEvolucao(this.mes, this.bruto, this.investido, this.liquido);
  final String mes;
  final double bruto, investido, liquido;
}

/// Bruto no fim de cada mês dos últimos `n` meses (o último é hoje).
List<PontoEvolucao> evolucaoMensal(Investimento inv, IndicesBcb? idx, String hoje, {int n = 12}) {
  final pontos = <PontoEvolucao>[];
  var mes = addMeses(primeiroDoMes(hoje), -(n - 1));
  for (var i = 0; i < n; i++) {
    final fimMes = addMeses(mes, 1);
    final data = fimMes.compareTo(hoje) > 0 ? hoje : fimMes;
    final p = posicao(inv, idx, data);
    pontos.add(PontoEvolucao(mesDe(mes), p.bruto, p.investido, p.liquido));
    mes = fimMes;
  }
  return pontos;
}
