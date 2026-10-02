/// Leitor de extrato e fatura — OFX, CSV e texto (PDF/print).
///
/// Porte fiel do leitor do Controle Total (`utils/extrato_import.dart`, que
/// por sua vez espelha `functions/extrato_import.js` do CT). Aqui é Dart puro:
/// sem Firebase, sem Flutter — testável em `test/extrato_import_test.dart`.
///
/// Sinal do valor — a regra que evita o erro mais caro:
///   num EXTRATO, negativo é despesa e positivo é receita;
///   numa FATURA em CSV, o positivo é a compra.
/// No **OFX o sinal já é a verdade**, inclusive na fatura: o extrato de cartão
/// do Nubank traz a compra como −15,96 e o pagamento da fatura como +979,83.
library;

/// Teto por arquivo: acima disso ninguém confere antes de confirmar.
const int kExtratoMaxItens = 150;

/// Um lançamento proposto pelo arquivo.
class ExtratoItem {
  ExtratoItem({
    required this.data,
    required this.descricao,
    required this.valor,
    required this.credito,
    this.categoria = '',
    this.pagamentoFatura = false,
    this.repetido = false,
    this.marcado = true,
    this.fitId = '',
  });

  final DateTime data;
  final String descricao;

  /// Sempre positivo — o sinal vive em [credito].
  final double valor;

  /// `true` = receita.
  final bool credito;

  /// Categoria escolhida (vazio enquanto não foi classificado).
  String categoria;

  /// Pagamento da própria fatura do cartão: não é receita, é o dinheiro
  /// saindo da conta para o cartão.
  final bool pagamentoFatura;

  /// Já existe um lançamento igual no app.
  bool repetido;

  /// Entra na gravação?
  bool marcado;

  final String fitId;

  ExtratoItem copyWith({
    DateTime? data,
    String? descricao,
    double? valor,
    bool? credito,
    String? categoria,
    bool? repetido,
    bool? marcado,
  }) =>
      ExtratoItem(
        data: data ?? this.data,
        descricao: descricao ?? this.descricao,
        valor: valor ?? this.valor,
        credito: credito ?? this.credito,
        categoria: categoria ?? this.categoria,
        pagamentoFatura: pagamentoFatura,
        repetido: repetido ?? this.repetido,
        marcado: marcado ?? this.marcado,
        fitId: fitId,
      );
}

/// O arquivo inteiro já lido.
class ExtratoLote {
  ExtratoLote({
    required this.formato,
    required this.fatura,
    required this.banco,
    required this.itens,
    required this.total,
    this.nomeArquivo = '',
  });

  /// `ofx`, `csv` ou `texto`.
  final String formato;

  /// O documento é fatura de cartão?
  final bool fatura;

  final String banco;
  final List<ExtratoItem> itens;

  /// Quantos o arquivo tinha (pode ser maior que `itens` por causa do teto).
  final int total;

  String nomeArquivo;

  bool get cortado => total > itens.length;

  /// Vira fatura em extrato (e vice-versa): troca o sinal de todos.
  ///
  /// Existe porque a detecção é palpite — quando o usuário diz que erramos, é
  /// uma troca de sinal, não uma releitura do arquivo.
  ExtratoLote inverterTipo() => ExtratoLote(
        formato: formato,
        fatura: !fatura,
        banco: banco,
        itens: itens.map((i) => i.copyWith(credito: !i.credito)).toList(),
        total: total,
        nomeArquivo: nomeArquivo,
      );
}

/// Soma de uma categoria, para o rateio.
class ExtratoGrupo {
  ExtratoGrupo(this.categoria, this.total, this.quantidade);
  final String categoria;
  final double total;
  final int quantidade;
}

/// Resumo do lote.
class ExtratoResumo {
  ExtratoResumo({
    required this.quantidade,
    required this.de,
    required this.ate,
    required this.despesas,
    required this.receitas,
    required this.totalDespesas,
    required this.totalReceitas,
  });

  final int quantidade;
  final DateTime? de;
  final DateTime? ate;
  final int despesas;
  final int receitas;
  final double totalDespesas;
  final double totalReceitas;
}

// ─────────────────────────── utilidades ───────────────────────────

/// Tira acento — o servidor faz o mesmo com `normalize("NFD")`.
///
/// Sem isso a chave de duplicata do app e a do servidor discordam: «Mercado
/// São José» viraria `mercadosojos` aqui e `mercadosaojose` lá, e o item
/// importado pelo Telegram não seria reconhecido como repetido no app.
String extratoSemAcento(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçÁÀÂÃÄÉÈÊËÍÌÎÏÓÒÔÕÖÚÙÛÜÇ';
  const para = 'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC';
  final b = StringBuffer();
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final i = de.indexOf(ch);
    b.write(i >= 0 ? para[i] : ch);
  }
  return b.toString();
}

String _normalizar(String? s) =>
    extratoSemAcento(s ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

double _arredondar(double v) => (v * 100).roundToDouble() / 100;

/// Número no formato brasileiro ou americano.
///
/// «1.234,56» é BR e «1,234.56» é US: quem manda é o separador que aparece por
/// ÚLTIMO. Adivinhar pelo primeiro trocaria 1.234 (mil) por 1,234 (um e pouco).
double? extratoNumero(String? v) {
  var t = (v ?? '').trim();
  if (t.isEmpty) return null;
  final negativo = RegExp(r'^\(.*\)$').hasMatch(t) ||
      t.startsWith('-') ||
      RegExp(r'-\s*$').hasMatch(t);
  t = t.replaceAll(RegExp(r'[R$\s()]', caseSensitive: false), '');
  t = t.replaceAll(RegExp(r'^-|-$'), '');
  if (t.isEmpty) return null;
  final ultimaVirgula = t.lastIndexOf(',');
  final ultimoPonto = t.lastIndexOf('.');
  if (ultimaVirgula >= 0 && ultimaVirgula > ultimoPonto) {
    t = t.replaceAll('.', '').replaceAll(',', '.');
  } else {
    t = t.replaceAll(',', '');
  }
  final n = double.tryParse(t);
  if (n == null) return null;
  return negativo ? -n.abs() : n;
}

DateTime? _dia(int a, int m, int d) {
  if (m < 1 || m > 12 || d < 1 || d > 31) return null;
  final dt = DateTime(a, m, d);
  return dt.month == m ? dt : null;
}

/// Data em qualquer formato que apareça em arquivo de banco.
///
/// `20261008` (OFX), `2026-10-08` (ISO), `08/10/2026` e `08/10` (sem ano — o
/// extrato do mês costuma omitir; aí vale o ano de referência).
DateTime? extratoData(String? v, [int? anoRef]) {
  final t = (v ?? '').trim();
  if (t.isEmpty) return null;
  final ano = anoRef ?? DateTime.now().year;

  var m = RegExp(r'^(\d{4})(\d{2})(\d{2})').firstMatch(t);
  if (m != null) {
    return _dia(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(t);
  if (m != null) {
    return _dia(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
  }
  m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})').firstMatch(t);
  if (m != null) {
    var a = int.parse(m[3]!);
    if (a < 100) a += 2000;
    return _dia(a, int.parse(m[2]!), int.parse(m[1]!));
  }
  m = RegExp(r'^(\d{1,2})[/.-](\d{1,2})$').firstMatch(t);
  if (m != null) {
    return _dia(ano, int.parse(m[2]!), int.parse(m[1]!));
  }
  return null;
}

/// Uma etiqueta do SGML do OFX: `<MEMO>PADARIA` (sem fechamento).
String _tag(String bloco, String nome) {
  final m = RegExp('<$nome>([^<\r\n]*)', caseSensitive: false).firstMatch(bloco);
  return m == null ? '' : m[1]!.trim();
}

/// «Pagamento recebido», «Pagto fatura», «Pagamento em …».
bool extratoEhPagamentoDeFatura(String descricao) =>
    RegExp(r'\b(pagamento|pagto|pgto)\b', caseSensitive: false)
        .hasMatch(_normalizar(descricao));

/// Tira o ruído que todo banco cola na descrição.
String _limparDescricao(String s) {
  var t = s
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'''^["']|["']$'''), '')
      .replaceAll(RegExp(r'\b\d{2}/\d{2}(/\d{2,4})?\b'), '')
      .replaceAll(RegExp(r'\s*-\s*\d{2}/\d{2}\s*$'), '')
      .replaceAll(
        RegExp(
          r'^(compra\s+(?:no\s+)?(?:cart[ãa]o|d[ée]bito|cr[ée]dito)\s*(?:-\s*)?)',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
  if (t.length > 90) t = t.substring(0, 90);
  return t.isEmpty ? 'Lançamento' : t;
}

/// Um item, já com o sinal resolvido.
///
/// `credito` é o que o app chama de receita. Numa fatura em CSV o valor
/// positivo é COMPRA (despesa) — o contrário do extrato.
ExtratoItem _montarItem({
  required DateTime data,
  required String descricao,
  required double valorComSinal,
  bool fatura = false,
  String id = '',
}) {
  final credito = fatura ? valorComSinal < 0 : valorComSinal > 0;
  return ExtratoItem(
    data: data,
    descricao: _limparDescricao(descricao),
    valor: _arredondar(valorComSinal.abs()),
    credito: credito,
    fitId: id.length > 64 ? id.substring(0, 64) : id,
  );
}

/// Nome do banco quando o arquivo diz.
String _nomeDoBanco(String texto) {
  final org = _tag(texto, 'ORG');
  if (org.isNotEmpty) return org.replaceAll('_', ' ').trim();
  const conhecidos = [
    'nubank', 'itau', 'bradesco', 'santander', 'caixa', 'banco do brasil',
    'inter', 'c6', 'sicoob', 'sicredi', 'will', 'neon', 'picpay',
    'mercado pago', 'original', 'safra', 'btg', 'banrisul', 'pan',
  ];
  final low =
      _normalizar(texto).toLowerCase();
  final recorte = low.length > 4000 ? low.substring(0, 4000) : low;
  for (final c in conhecidos) {
    if (recorte.contains(c)) {
      return c.split(' ').map((p) => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}').join(' ');
    }
  }
  return '';
}

// ──────────────────────────────── OFX ────────────────────────────────

ExtratoLote? extratoLerOFX(String bruto) {
  if (!RegExp('<STMTTRN>', caseSensitive: false).hasMatch(bruto)) return null;

  final fatura =
      RegExp('<CREDITCARDMSGSRSV1|<CCSTMTRS', caseSensitive: false).hasMatch(bruto);
  final banco = _nomeDoBanco(bruto);
  final itens = <ExtratoItem>[];
  final blocos = bruto.split(RegExp('<STMTTRN>', caseSensitive: false)).skip(1);
  for (final b in blocos) {
    final corpo = b.split(RegExp(r'</STMTTRN>', caseSensitive: false)).first;
    final dt = extratoData(_tag(corpo, 'DTPOSTED'));
    final valor = extratoNumero(_tag(corpo, 'TRNAMT'));
    if (dt == null || valor == null || valor == 0) continue;
    final memo = _tag(corpo, 'MEMO').isNotEmpty ? _tag(corpo, 'MEMO') : _tag(corpo, 'NAME');
    // No OFX o sinal JÁ é a verdade, inclusive na fatura: inverter por ser
    // fatura (como o CSV exige) viraria toda compra em receita.
    final base = _montarItem(
      data: dt,
      descricao: memo.isNotEmpty ? memo : (_tag(corpo, 'TRNTYPE').isNotEmpty ? _tag(corpo, 'TRNTYPE') : 'Lançamento'),
      valorComSinal: valor,
      id: _tag(corpo, 'FITID'),
    );
    // Pagamento da própria fatura não é receita.
    final ehPagamento =
        fatura && base.credito && extratoEhPagamentoDeFatura(base.descricao);
    itens.add(ExtratoItem(
      data: base.data,
      descricao: base.descricao,
      valor: base.valor,
      credito: base.credito,
      pagamentoFatura: ehPagamento,
      marcado: !ehPagamento,
      fitId: base.fitId,
    ));
  }
  if (itens.isEmpty) return null;
  return ExtratoLote(
    formato: 'ofx',
    fatura: fatura,
    banco: banco,
    itens: itens.take(kExtratoMaxItens).toList(),
    total: itens.length,
  );
}

// ──────────────────────────────── CSV ────────────────────────────────

String? _separadorDe(String linha) {
  const cand = [';', ',', '\t'];
  String melhor = ';';
  int n = -1;
  for (final c in cand) {
    final q = linha.split(c).length - 1;
    if (q > n) {
      n = q;
      melhor = c;
    }
  }
  return n > 0 ? melhor : null;
}

/// Quebra uma linha de CSV respeitando aspas.
List<String> extratoCampos(String linha, String sep) {
  final out = <String>[];
  final buf = StringBuffer();
  var aspas = false;
  for (var i = 0; i < linha.length; i++) {
    final c = linha[i];
    if (c == '"') {
      if (aspas && i + 1 < linha.length && linha[i + 1] == '"') {
        buf.write('"');
        i++;
      } else {
        aspas = !aspas;
      }
    } else if (c == sep && !aspas) {
      out.add(buf.toString().trim());
      buf.clear();
    } else {
      buf.write(c);
    }
  }
  out.add(buf.toString().trim());
  return out;
}

final _cabData = RegExp(
    r'^(data|date|dt|data\s*(de\s*)?(lan[çc]amento|compra|movimenta|transa))',
    caseSensitive: false);
final _cabDesc = RegExp(
    r'(descri|hist[óo]rico|lan[çc]amento|estabelecimento|t[íi]tulo|title|memo|detalhe|movimenta)',
    caseSensitive: false);
final _cabValor = RegExp(
    r'^(valor|amount|value|montante|cr[ée]dito|d[ée]bito)',
    caseSensitive: false);

ExtratoLote? extratoLerCSV(String bruto) {
  final linhas = bruto
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();
  if (linhas.length < 2) return null;

  final sep = _separadorDe(linhas.first);
  if (sep == null) return null;

  final cab = extratoCampos(linhas.first, sep);
  final temCabecalho = cab.any((c) => _cabData.hasMatch(c)) &&
      cab.any((c) => _cabValor.hasMatch(c) || _cabDesc.hasMatch(c));
  var iData = -1;
  var iDesc = -1;
  var iValor = -1;
  if (temCabecalho) {
    for (var i = 0; i < cab.length; i++) {
      if (iData < 0 && _cabData.hasMatch(cab[i])) iData = i;
      if (iValor < 0 && _cabValor.hasMatch(cab[i])) iValor = i;
      if (iDesc < 0 && _cabDesc.hasMatch(cab[i])) iDesc = i;
    }
  }

  final corpo = temCabecalho ? linhas.sublist(1) : linhas;
  final anoRef = DateTime.now().year;
  final brutos = <({DateTime data, String descricao, double valor})>[];
  for (final l in corpo) {
    final c = extratoCampos(l, sep);
    if (c.length < 2) continue;

    DateTime? dt = iData >= 0 && iData < c.length ? extratoData(c[iData], anoRef) : null;
    double? valor = iValor >= 0 && iValor < c.length ? extratoNumero(c[iValor]) : null;
    var desc = iDesc >= 0 && iDesc < c.length ? c[iDesc] : '';

    dt ??= c.map((x) => extratoData(x, anoRef)).firstWhere((x) => x != null, orElse: () => null);
    if (valor == null || valor == 0) {
      // De trás para frente: o valor costuma ser a última coluna numérica, e o
      // saldo (quando existe) vem DEPOIS.
      for (var k = c.length - 1; k >= 0; k--) {
        final n = extratoNumero(c[k]);
        if (n != null && n != 0 && extratoData(c[k], anoRef) == null) {
          valor = n;
          break;
        }
      }
    }
    if (desc.isEmpty) {
      final candidatos = c
          .where((x) => extratoData(x, anoRef) == null && extratoNumero(x) == null)
          .toList()
        ..sort((a, b) => b.length.compareTo(a.length));
      desc = candidatos.isEmpty ? '' : candidatos.first;
    }
    if (dt == null || valor == null || valor == 0) continue;
    brutos.add((data: dt, descricao: desc, valor: valor));
  }
  if (brutos.length < 2) return null; // uma linha só é palpite, não extrato

  // Fatura de cartão × extrato de conta: a fatura em CSV (a do Nubank é
  // «date,title,amount») traz a COMPRA como positiva. Nenhum débito em três ou
  // mais linhas não acontece num extrato de conta — então é fatura.
  final fatura = brutos.length >= 3 && !brutos.any((b) => b.valor < 0);
  final itens = brutos
      .map((b) => _montarItem(
            data: b.data,
            descricao: b.descricao,
            valorComSinal: b.valor,
            fatura: fatura,
          ))
      .toList();
  return ExtratoLote(
    formato: 'csv',
    fatura: fatura,
    banco: '',
    itens: itens.take(kExtratoMaxItens).toList(),
    total: itens.length,
  );
}

// ─────────────────────── texto (PDF / print) ───────────────────────

final _linhaMov = RegExp(
  r'^(\d{1,2}[/.-]\d{1,2}(?:[/.-]\d{2,4})?)\s+(.{3,60}?)\s+(-?\s*R?\$?\s*\d{1,3}(?:[.\s]\d{3})*(?:,\d{2})|-?\s*R?\$?\s*\d+[.,]\d{2})\s*([CD])?$',
  caseSensitive: false,
);

/// Linhas que nunca são movimento, por mais que casem com o formato.
final _linhaRuim = RegExp(
  r'(saldo|total\s+(da\s+fatura|a\s+pagar|geral)|limite|pagamento\s+m[íi]nimo|encargos|juros\s+do\s+m[êe]s|subtotal|vencimento|per[íi]odo)',
  caseSensitive: false,
);

ExtratoLote? extratoLerTexto(String bruto, {bool? fatura}) {
  if (bruto.trim().isEmpty) return null;
  final ehFatura = fatura ??
      RegExp(r'fatura|cart[ãa]o de cr[ée]dito|limite\s+total|pagamento\s+m[íi]nimo',
              caseSensitive: false)
          .hasMatch(bruto);
  final m = RegExp(r'\b(20\d{2})\b').firstMatch(bruto);
  final anoRef = m == null ? DateTime.now().year : int.parse(m[1]!);

  final itens = <ExtratoItem>[];
  for (final linhaBruta in bruto.split(RegExp(r'\r?\n'))) {
    final l = linhaBruta.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
    if (l.isEmpty || _linhaRuim.hasMatch(l)) continue;
    final mm = _linhaMov.firstMatch(l);
    if (mm == null) continue;
    final dt = extratoData(mm[1], anoRef);
    var valor = extratoNumero(mm[3]);
    if (dt == null || valor == null || valor == 0) continue;
    final marca = (mm[4] ?? '').toUpperCase();
    if (marca == 'C') valor = valor.abs();
    if (marca == 'D') valor = -valor.abs();
    itens.add(_montarItem(
      data: dt,
      descricao: mm[2]!,
      valorComSinal: valor,
      fatura: ehFatura && marca.isEmpty,
    ));
  }
  if (itens.length < 2) return null;
  return ExtratoLote(
    formato: 'texto',
    fatura: ehFatura,
    banco: _nomeDoBanco(bruto),
    itens: itens.take(kExtratoMaxItens).toList(),
    total: itens.length,
  );
}

// ───────────────────────────── entrada ─────────────────────────────

/// Ponto único: recebe o conteúdo e devolve a lista, seja qual for o formato.
///
/// `nomeArquivo` só ajuda a escolher por onde começar — o conteúdo é quem
/// decide, porque CSV renomeado para .txt continua sendo CSV.
ExtratoLote? extratoInterpretar(String bruto, {String nomeArquivo = ''}) {
  final nome = nomeArquivo.toLowerCase();
  final inicio = bruto.length > 4000 ? bruto.substring(0, 4000) : bruto;

  if (RegExp(r'\.(ofx|qfx)$').hasMatch(nome) ||
      RegExp('<OFX>|<STMTTRN>', caseSensitive: false).hasMatch(inicio)) {
    final r = extratoLerOFX(bruto);
    if (r != null) return r..nomeArquivo = nomeArquivo;
  }
  final primeiraLinha = bruto.split(RegExp(r'\r?\n')).firstWhere((_) => true, orElse: () => '');
  if (RegExp(r'\.(csv|tsv)$').hasMatch(nome) ||
      RegExp(r'[;,\t]').hasMatch(primeiraLinha)) {
    final r = extratoLerCSV(bruto);
    if (r != null) return r..nomeArquivo = nomeArquivo;
  }
  final r = extratoLerTexto(bruto);
  return r == null ? null : (r..nomeArquivo = nomeArquivo);
}

/// Em que fatura a compra cai — porte fiel de `refDaCompra` em
/// `functions/cartao_faturas.js`.
///
/// Compra NO dia do fechamento já é da fatura SEGUINTE (o «melhor dia de
/// compra»; Nubank do dono em 01/10/2026: compras de 01 OUT na fatura de
/// novembro). Sem dia de fechamento cadastrado, a fatura é a do mês da
/// compra — melhor do que não agrupar nada. Mês com menos dias que o
/// fechamento (fechamento 31 em fevereiro) fecha no último dia.
String extratoRefDaCompra(DateTime compra, int? diaFechamento) {
  String chave(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}';
  final d = DateTime(compra.year, compra.month, compra.day);
  final dia = diaFechamento ?? 0;
  if (dia < 1 || dia > 31) return chave(d);
  final ultimo = DateTime(d.year, d.month + 1, 0).day;
  final fechamentoDoMes = dia < ultimo ? dia : ultimo;
  if (d.day < fechamentoDoMes) return chave(d);
  return chave(DateTime(d.year, d.month + 1, 1));
}

/// Chave de duplicata: dia + valor + começo da descrição.
///
/// Sem isso, importar o OFX de um banco já conectado ao Open Finance dobraria
/// o mês inteiro — e o saldo passaria a mentir.
String extratoChaveItem({
  required DateTime data,
  required double valor,
  required bool credito,
  required String descricao,
}) {
  final dia = '${data.year}-${data.month.toString().padLeft(2, '0')}-'
      '${data.day.toString().padLeft(2, '0')}';
  var desc = _normalizar(descricao)
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]'), '');
  if (desc.length > 14) desc = desc.substring(0, 14);
  return '$dia|${valor.toStringAsFixed(2)}|${credito ? 'c' : 'd'}|$desc';
}

/// Chave de duplicata de um lançamento JÁ gravado em
/// `users/{uid}/transactions` (campos `date`, `amount`, `type`,
/// `description`/`category`). [data] vem à parte porque o `date` do Firestore
/// é `Timestamp` — quem lê converte; aqui fica a regra pura.
String extratoChaveDeLancamento(Map<String, dynamic> d, DateTime data) =>
    extratoChaveItem(
      data: data,
      valor: ((d['amount'] as num?) ?? 0).toDouble().abs(),
      credito: (d['type'] ?? 'expense').toString() == 'income',
      descricao: (d['description'] ?? d['category'] ?? '').toString(),
    );

/// Marca como repetido (e DESMARCA) o que já existe no app.
///
/// O repetido fica desmarcado, não escondido: esconder faria o arquivo
/// parecer incompleto. Devolve quantos foram marcados.
int extratoMarcarRepetidos(List<ExtratoItem> itens, Set<String> chavesExistentes) {
  if (chavesExistentes.isEmpty) return 0;
  var n = 0;
  for (final i in itens) {
    final chave = extratoChaveItem(
      data: i.data,
      valor: i.valor,
      credito: i.credito,
      descricao: i.descricao,
    );
    if (chavesExistentes.contains(chave)) {
      i.repetido = true;
      i.marcado = false;
      n++;
    }
  }
  return n;
}

/// Campos do documento em `users/{uid}/transactions` que dependem só do item
/// (sem data/Timestamp nem `serverTimestamp`, que o serviço acrescenta).
///
/// Regras do Controle Total mantidas:
///   - extrato de conta: já aconteceu → `paid`;
///   - compra de FATURA num cartão → `pending` + `cartaoCredito`/`faturaRef`
///     (só pesa no saldo ao pagar a fatura);
///   - «Pagamento recebido» (pagamento da própria fatura) → `faturaPagamento:
///     true`: fica fora dos totais de receita/despesa (ver
///     `utils/finance_fora_dos_totais.dart`) e nunca vira compra pendente.
Map<String, dynamic> extratoCamposDoLancamento(
  ExtratoItem i, {
  required String contaId,
  String origem = 'extrato_import',
  bool faturaDeCartao = false,
  int? diaFechamento,
}) {
  final compraDeCartao = faturaDeCartao && !i.pagamentoFatura;
  return {
    'type': i.credito ? 'income' : 'expense',
    'amount': i.valor.abs(),
    'category': i.categoria.isEmpty ? 'Outros' : i.categoria,
    'description': i.descricao,
    'status': compraDeCartao ? 'pending' : 'paid',
    if (compraDeCartao) ...{
      'cartaoCredito': true,
      'faturaRef': extratoRefDaCompra(i.data, diaFechamento),
    },
    if (i.pagamentoFatura) 'faturaPagamento': true,
    'recurrence': 'none',
    'installmentCount': 1,
    'installmentIndex': 1,
    'source': origem,
    'addToCalendar': false,
    'hideFromCalendar': false,
    if (i.fitId.isNotEmpty) 'extratoFitId': i.fitId,
    if (contaId.isNotEmpty) 'financeAccountId': contaId,
  };
}

/// Resumo para o cabeçalho: período, contagem e somas.
///
/// Pagamento da fatura não entra nas somas (é dinheiro mudando de lugar).
ExtratoResumo extratoResumir(List<ExtratoItem> todos) {
  final itens = todos.where((i) => !i.pagamentoFatura).toList();
  final datas = itens.map((i) => i.data).toList()..sort();
  final despesas = itens.where((i) => !i.credito).toList();
  final receitas = itens.where((i) => i.credito).toList();
  double soma(List<ExtratoItem> l) =>
      _arredondar(l.fold<double>(0, (s, i) => s + i.valor));
  return ExtratoResumo(
    quantidade: itens.length,
    de: datas.isEmpty ? null : datas.first,
    ate: datas.isEmpty ? null : datas.last,
    despesas: despesas.length,
    receitas: receitas.length,
    totalDespesas: soma(despesas),
    totalReceitas: soma(receitas),
  );
}

/// Soma por categoria, da maior para a menor.
///
/// É o que a pessoa quer ver antes de confirmar: «gastei 2.100 em Alimentação»
/// responde mais rápido que 58 linhas.
List<ExtratoGrupo> extratoPorCategoria(List<ExtratoItem> itens) {
  final mapa = <String, ({double total, int quantidade})>{};
  for (final i in itens) {
    final k = i.categoria.isEmpty ? 'Outros' : i.categoria;
    final atual = mapa[k] ?? (total: 0.0, quantidade: 0);
    mapa[k] = (total: atual.total + i.valor, quantidade: atual.quantidade + 1);
  }
  final out = mapa.entries
      .map((e) => ExtratoGrupo(e.key, _arredondar(e.value.total), e.value.quantidade))
      .toList()
    ..sort((a, b) => b.total.compareTo(a.total));
  return out;
}
