import '../constants/app_business_rules.dart';
import '../constants/finance_bank_presets.dart';
import '../utils/ocr_description_sanity.dart';

/// Resultado do parse de SMS / push de banco (regex no cliente — custo zero).
class BankNotificationParseResult {
  /// Valor numérico positivo (ex.: 9.0 para R$ 9,00).
  final double? valor;
  final DateTime? data;
  final String? descricao;

  /// `expense` = compra/débito/saque; `income` = pix recebido / crédito / TED entrada.
  final String type;

  /// Sugestão de [FinanceBankPreset.id] a partir do texto (ex.: bradesco).
  final String? suggestedPresetId;

  /// Trecho original normalizado para debug / aprendizado de categoria.
  final String rawSnippet;

  const BankNotificationParseResult({
    required this.valor,
    required this.data,
    required this.descricao,
    required this.type,
    required this.suggestedPresetId,
    required this.rawSnippet,
  });

  bool get hasMinimumForConfirmation => valor != null && valor! > 0 && descricao != null && descricao!.trim().isNotEmpty;

  BankNotificationParseResult copyWith({
    String? suggestedPresetId,
    double? valor,
    DateTime? data,
    String? descricao,
    String? rawSnippet,
  }) {
    return BankNotificationParseResult(
      valor: valor ?? this.valor,
      data: data ?? this.data,
      descricao: descricao ?? this.descricao,
      type: type,
      suggestedPresetId: suggestedPresetId ?? this.suggestedPresetId,
      rawSnippet: rawSnippet ?? this.rawSnippet,
    );
  }
}

/// Extrai valor, data, estabelecimento e tipo (débito/crédito) de mensagens de banco.
abstract final class BankNotificationParser {
  BankNotificationParser._();

  /// Limite de linhas devolvidas em [parseManyForBatch] (performance / Firestore).
  static const int kMaxBatchParseRows = 200;

  /// Caracteres máximos analisados (colagens gigantes / PDF como texto travam o UI na web).
  static const int kMaxParseInputChars = 100000;

  /// Uma passagem de [parseManyForBatch]: primeiro lançamento para o cartão de confirmação + total para massa.
  /// Evita chamar [parse] no texto inteiro e depois [parseManyForBatch] de novo (dobro de trabalho).
  static (BankNotificationParseResult preview, int batchCount) parseForSmartInputField(String texto) {
    final batch = parseManyForBatch(texto);
    if (batch.isNotEmpty) {
      return (batch.first, batch.length);
    }
    final p = parse(texto);
    return (p, batch.length);
  }

  /// Parse de CSV de fatura/extrato exportado por **qualquer banco** (nomes de coluna variados).
  /// Deteta separador `,`, `;` ou TAB; mapeia data, descrição e valor (ou colunas débito/crédito);
  /// colunas extra (memo, merchant, category) são concatenadas à descrição quando existem.
  /// normaliza para [BankNotificationParseResult] (valor > 0, data, descrição, tipo receita/despesa).
  static List<BankNotificationParseResult> parseFromCsvText(String csvText) {
    var text = csvText.replaceAll('\r', '\n').trim();
    if (text.startsWith('\ufeff')) {
      text = text.substring(1);
    }
    if (text.isEmpty) return const [];

    final lines = text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.length < 2) return const [];

    final sep = _detectCsvSeparator(lines.first);
    final headerRaw = _splitCsvLine(lines.first, sep);
    final header = headerRaw.map(_normalizeCsvHeaderCell).toList();
    if (header.length < 2) return const [];

    final idx = _resolveCsvColumnIndices(header, lines, sep);
    if (idx == null) return const [];

    final out = <BankNotificationParseResult>[];
    for (final raw in lines.skip(1)) {
      final row = _splitCsvLine(raw, sep);
      if (row.isEmpty) continue;

      var desc = _normalizeCsvDescription(_csvAt(row, idx.descIdx));
      desc = _enrichCsvRowDescription(desc, row, idx.memoIdx, idx.merchantIdx, idx.categoryIdx);
      if (desc.length < 2) continue;

      double? signedAmt;
      if (idx.debitIdx != null || idx.creditIdx != null) {
        final rawD = idx.debitIdx != null ? _csvAt(row, idx.debitIdx!).trim() : '';
        final rawC = idx.creditIdx != null ? _csvAt(row, idx.creditIdx!).trim() : '';
        final d = rawD.isNotEmpty ? _parseDecimalFlexible(rawD) : null;
        final c = rawC.isNotEmpty ? _parseDecimalFlexible(rawC) : null;
        // Débito → despesa (valor interno > 0); crédito → receita (valor interno < 0), alinhado à coluna única com sinal.
        if (d != null && d.abs() > 0) {
          signedAmt = d.abs();
        } else if (c != null && c.abs() > 0) {
          signedAmt = -c.abs();
        }
      } else {
        final amountRaw = _csvAt(row, idx.amountIdx!).trim();
        if (amountRaw.isEmpty) continue;
        signedAmt = _parseDecimalFlexible(amountRaw);
      }

      if (signedAmt == null || signedAmt == 0) continue;
      final amountAbs = signedAmt.abs();
      if (amountAbs <= 0) continue;

      final dateRaw = _csvAt(row, idx.dateIdx).trim();
      final dt = _parseDateFlexible(dateRaw) ?? DateTime.now();
      final type = signedAmt < 0 ? 'income' : 'expense';

      final snippet = raw.length > 400 ? raw.substring(0, 400) : raw;
      out.add(
        BankNotificationParseResult(
          valor: amountAbs,
          data: dt,
          descricao: desc,
          type: type,
          suggestedPresetId: _suggestBankPreset(desc),
          rawSnippet: snippet,
        ),
      );
      if (out.length >= kMaxBatchParseRows) break;
    }
    return out.map(_sanitizeDescInResult).toList();
  }

  static String _normalizeCsvHeaderCell(String cell) {
    var s = cell.trim().toLowerCase();
    if (s.startsWith('\ufeff')) s = s.substring(1);
    s = s.replaceAll(RegExp(r'[\s_]+'), ' ');
    return s;
  }

  static String _normalizeCsvDescription(String s) {
    var t = s.replaceAll('"', '').trim();
    t = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    return t;
  }

  static final RegExp _csvHeaderNoise = RegExp(
    r'^(unnamed|n\.?º|no\.?|#|id|codigo|código|agencia|agência|conta|parcela|doc\.?|documento)\b',
    caseSensitive: false,
  );

  static int _csvHeaderScoreDate(String h) {
    if (h.isEmpty || _csvHeaderNoise.hasMatch(h)) return 0;
    var s = 0;
    if (h == 'data' || h == 'date' || h == 'dt') s += 12;
    if (h.contains('data ') || h.startsWith('data ')) s += 10;
    if (h.contains('date') || h.contains('data')) s += 6;
    if (h.contains('movimen') || h.contains('transac') || h.contains('transaction')) s += 8;
    if (h.contains('posting') || h.contains('booked') || h.contains('realiz')) s += 6;
    if (h.contains('pagamento') && h.contains('data')) s += 5;
    if (h.contains('lançamento') || h.contains('lancamento')) s += 5;
    if (h.contains('venc') || h.contains('due')) s += 3;
    return s;
  }

  static int _csvHeaderScoreDesc(String h) {
    if (h.isEmpty || _csvHeaderNoise.hasMatch(h)) return 0;
    var s = 0;
    const keys = <String>[
      'historico',
      'histórico',
      'descricao',
      'descrição',
      'description',
      'memo',
      'narrative',
      'title',
      'estabelec',
      'merchant',
      'payee',
      'beneficiar',
      'favorecido',
      'detalhe',
      'details',
      'lancamento',
      'lançamento',
      'movimento',
      'identificacao',
      'identificação',
    ];
    for (final k in keys) {
      if (h.contains(k)) s += 8;
    }
    if (h == 'title' || h == 'memo') s += 10;
    return s;
  }

  static int _csvHeaderScoreAmount(String h) {
    if (h.isEmpty || _csvHeaderNoise.hasMatch(h)) return 0;
    if (h.contains('saldo') && !h.contains('valor')) return 1;
    var s = 0;
    if (h == 'amount' || h == 'valor' || h == 'value') s += 14;
    if (h.contains('valor') && !h.contains('saldo')) s += 10;
    if (h.contains('amount') && !h.contains('document')) s += 8;
    if (h.contains('total') && !h.contains('parcela')) s += 6;
    if (h.contains('débito') || h.contains('debito') || h == 'debit' || h.contains(' debit')) s += 9;
    if (h.contains('crédito') || h.contains('credito') || h == 'credit' || h.contains(' credit')) s += 9;
    if (h.contains('entrada') || h.contains('saidas') || h.contains('saídas')) s += 4;
    if (h.contains('brl') || h.contains('r\$')) s += 5;
    return s;
  }

  static int _csvHeaderScoreDebit(String h) {
    if (h.isEmpty) return 0;
    if (h.contains('credito') || h.contains('crédito') || h.contains('credit')) return 0;
    if (h.contains('débito') || h.contains('debito') || (h.contains('debit') && !h.contains('card'))) return 10;
    if (h.contains('saidas') || h.contains('saídas') || h.contains('saida')) return 8;
    return 0;
  }

  static int _csvHeaderScoreCredit(String h) {
    if (h.isEmpty) return 0;
    if (h.contains('débito') || h.contains('debito') || (h.contains('debit') && !h.contains('card'))) return 0;
    if (h.contains('crédito') || h.contains('credito') || h.contains('credit')) return 10;
    if (h.contains('entradas') || h.contains('entrada')) return 7;
    return 0;
  }

  /// Colunas tipo “notas” / complemento (não devem substituir a descrição principal).
  static int _csvHeaderScoreMemo(String h) {
    if (h.isEmpty || _csvHeaderNoise.hasMatch(h)) return 0;
    if (h == 'memo' || h == 'notes' || h == 'nota' || h == 'notas') return 14;
    if (h.contains('memo') && !h.contains('memorando')) return 10;
    if (h.contains('notes') || h.contains('notas')) return 9;
    if (h.contains('observa') || h.contains('coment') || h.contains('comment')) return 8;
    if (h.contains('additional') || h.contains('supplement') || h.contains('complemento')) return 7;
    if (h.contains('reference') || h.contains('referência') || h.contains('referencia')) return 6;
    return 0;
  }

  /// Estabelecimento / contraparte (segunda coluna de texto muito comum em exportações).
  static int _csvHeaderScoreMerchant(String h) {
    if (h.isEmpty || _csvHeaderNoise.hasMatch(h)) return 0;
    if (h == 'merchant' || h == 'payee' || h == 'vendor') return 14;
    if (h.contains('merchant') || h.contains('payee') || h.contains('vendor')) return 12;
    if (h.contains('estabelec') || h.contains('counterparty') || h.contains('benefici')) return 10;
    if (h.contains('favorecido') && !h.contains('conta')) return 9;
    if (h.contains('store') || h.contains('loja ') || h == 'loja') return 7;
    if (h.contains('nome fantasia') || h.contains('fantasia')) return 8;
    return 0;
  }

  static int _csvHeaderScoreCategory(String h) {
    if (h.isEmpty || _csvHeaderNoise.hasMatch(h)) return 0;
    if (h.contains('categor')) return 14;
    if (h.contains('classifica') && !h.contains('documento')) return 9;
    if (h.contains('tipo de gasto') || h.contains('tipo gasto')) return 10;
    if (h == 'class' || h.startsWith('class ') || h.contains(' mcc')) return 5;
    if (h.contains('budget') || h.contains('orçamento') || h.contains('orcamento')) return 6;
    return 0;
  }

  static int _argMaxScore(List<int> scores) {
    var bestI = 0;
    var bestV = -1;
    for (var i = 0; i < scores.length; i++) {
      if (scores[i] > bestV) {
        bestV = scores[i];
        bestI = i;
      }
    }
    return bestI;
  }

  static ({int dateIdx, int descIdx, int? amountIdx, int? debitIdx, int? creditIdx, int? memoIdx, int? merchantIdx, int? categoryIdx})?
      _resolveCsvColumnIndices(
    List<String> header,
    List<String> lines,
    String sep,
  ) {
    final n = header.length;
    if (n < 2) return null;

    final dateScores = List<int>.generate(n, (i) => _csvHeaderScoreDate(header[i]));
    final descScores = List<int>.generate(n, (i) => _csvHeaderScoreDesc(header[i]));
    final amtScores = List<int>.generate(n, (i) => _csvHeaderScoreAmount(header[i]));
    final debScores = List<int>.generate(n, (i) => _csvHeaderScoreDebit(header[i]));
    final credScores = List<int>.generate(n, (i) => _csvHeaderScoreCredit(header[i]));

    int? debitIdx = debScores.reduce((a, b) => a > b ? a : b) >= 6 ? _argMaxScore(debScores) : null;
    int? creditIdx = credScores.reduce((a, b) => a > b ? a : b) >= 6 ? _argMaxScore(credScores) : null;
    if (debitIdx != null && creditIdx != null && debitIdx == creditIdx) {
      creditIdx = null;
    }

    int? amountIdx;
    if (debitIdx == null && creditIdx == null) {
      final bestAmt = amtScores.reduce((a, b) => a > b ? a : b);
      if (bestAmt >= 4) {
        amountIdx = _argMaxScore(amtScores);
      }
    }

    var dateIdx = _argMaxScore(dateScores);
    if (dateScores[dateIdx] < 4) {
      dateIdx = _inferDateColumnFromSample(lines, sep) ?? 0;
    }

    var descIdx = _argMaxScore(descScores);
    if (descScores[descIdx] < 4) {
      descIdx = _inferDescColumnFromSample(header, lines, sep, dateIdx, amountIdx, debitIdx, creditIdx);
    }

    if (debitIdx != null || creditIdx != null) {
      descIdx = _ensureDistinctColumn(descIdx, {dateIdx, if (debitIdx != null) debitIdx, if (creditIdx != null) creditIdx}, n);
      dateIdx = _ensureDistinctColumn(dateIdx, {descIdx, if (debitIdx != null) debitIdx, if (creditIdx != null) creditIdx}, n);
      final extra = _resolveCsvEnrichmentIndices(
        header,
        n,
        dateIdx,
        descIdx,
        amountIdx: null,
        debitIdx: debitIdx,
        creditIdx: creditIdx,
      );
      return (
        dateIdx: dateIdx,
        descIdx: descIdx,
        amountIdx: null,
        debitIdx: debitIdx,
        creditIdx: creditIdx,
        memoIdx: extra.memoIdx,
        merchantIdx: extra.merchantIdx,
        categoryIdx: extra.categoryIdx,
      );
    }

    amountIdx ??= _inferAmountColumnFromSample(lines, sep, dateIdx, descIdx);
    if (amountIdx == null) return null;

    descIdx = _ensureDistinctColumn(descIdx, {dateIdx, amountIdx}, n);
    dateIdx = _ensureDistinctColumn(dateIdx, {descIdx, amountIdx}, n);
    descIdx = _ensureDistinctColumn(descIdx, {dateIdx, amountIdx}, n);

    final extra2 = _resolveCsvEnrichmentIndices(
      header,
      n,
      dateIdx,
      descIdx,
      amountIdx: amountIdx,
      debitIdx: null,
      creditIdx: null,
    );
    return (
      dateIdx: dateIdx,
      descIdx: descIdx,
      amountIdx: amountIdx,
      debitIdx: null,
      creditIdx: null,
      memoIdx: extra2.memoIdx,
      merchantIdx: extra2.merchantIdx,
      categoryIdx: extra2.categoryIdx,
    );
  }

  static ({int? memoIdx, int? merchantIdx, int? categoryIdx}) _resolveCsvEnrichmentIndices(
    List<String> header,
    int n,
    int dateIdx,
    int descIdx, {
    required int? amountIdx,
    required int? debitIdx,
    required int? creditIdx,
  }) {
    final used = <int>{
      dateIdx,
      descIdx,
      if (amountIdx != null) amountIdx,
      if (debitIdx != null) debitIdx,
      if (creditIdx != null) creditIdx,
    };

    int? pick(int Function(String h) score, int minScore) {
      var bestI = -1;
      var bestS = -1;
      for (var i = 0; i < n; i++) {
        if (used.contains(i)) continue;
        final s = score(header[i]);
        if (s >= minScore && s > bestS) {
          bestS = s;
          bestI = i;
        }
      }
      if (bestI < 0) return null;
      used.add(bestI);
      return bestI;
    }

    final memoIdx = pick(_csvHeaderScoreMemo, 6);
    final merchantIdx = pick(_csvHeaderScoreMerchant, 6);
    final categoryIdx = pick(_csvHeaderScoreCategory, 6);
    return (memoIdx: memoIdx, merchantIdx: merchantIdx, categoryIdx: categoryIdx);
  }

  /// Concatena memo → merchant → category à descrição principal (ordem pedida), sem duplicar texto idêntico.
  /// Se a descrição principal estiver vazia, usa só as colunas extra quando tiverem texto.
  static String _enrichCsvRowDescription(
    String baseDesc,
    List<String> row,
    int? memoIdx,
    int? merchantIdx,
    int? categoryIdx,
  ) {
    var out = baseDesc.trim();
    final seen = <String>{};
    if (out.isNotEmpty) seen.add(out.toLowerCase());

    void appendPart(int? colIdx) {
      if (colIdx == null || colIdx >= row.length) return;
      final t = _normalizeCsvDescription(_csvAt(row, colIdx));
      if (t.length < 2) return;
      final k = t.toLowerCase();
      if (seen.contains(k)) return;
      seen.add(k);
      out = out.isEmpty ? t : '$out · $t';
    }

    appendPart(memoIdx);
    appendPart(merchantIdx);
    appendPart(categoryIdx);
    return _normalizeCsvDescription(out);
  }

  static int _ensureDistinctColumn(int preferred, Set<int> taken, int n) {
    if (!taken.contains(preferred)) return preferred;
    for (var k = 0; k < n; k++) {
      final i = (preferred + k) % n;
      if (!taken.contains(i)) return i;
    }
    return preferred;
  }

  static int? _inferDateColumnFromSample(List<String> lines, String sep) {
    if (lines.length < 2) return null;
    final sample = lines.skip(1).take(8).toList();
    final firstRow = _splitCsvLine(lines.first, sep);
    final cols = firstRow.length;
    var bestCol = 0;
    var bestHits = 0;
    for (var c = 0; c < cols; c++) {
      var hits = 0;
      for (final raw in sample) {
        final row = _splitCsvLine(raw, sep);
        if (c >= row.length) continue;
        if (_parseDateFlexible(row[c].trim()) != null) hits++;
      }
      if (hits > bestHits) {
        bestHits = hits;
        bestCol = c;
      }
    }
    return bestHits >= 2 ? bestCol : null;
  }

  static int _inferDescColumnFromSample(
    List<String> header,
    List<String> lines,
    String sep,
    int dateIdx,
    int? amountIdx,
    int? debitIdx,
    int? creditIdx,
  ) {
    final skip = <int>{dateIdx};
    if (amountIdx != null) skip.add(amountIdx);
    if (debitIdx != null) skip.add(debitIdx);
    if (creditIdx != null) skip.add(creditIdx);

    var best = 0;
    var bestLen = -1;
    for (var i = 0; i < header.length; i++) {
      if (skip.contains(i)) continue;
      if (_csvHeaderScoreAmount(header[i]) >= 8) continue;
      if (_csvHeaderScoreDate(header[i]) >= 8 && i != dateIdx) continue;
      var len = 0;
      for (final raw in lines.skip(1).take(6)) {
        final row = _splitCsvLine(raw, sep);
        if (i < row.length) len += row[i].trim().length;
      }
      if (len > bestLen) {
        bestLen = len;
        best = i;
      }
    }
    if (bestLen < 0) {
      for (var i = 0; i < header.length; i++) {
        if (!skip.contains(i)) return i;
      }
      return 0;
    }
    return best;
  }

  static int? _inferAmountColumnFromSample(List<String> lines, String sep, int dateIdx, int descIdx) {
    if (lines.length < 2) return null;
    final sample = lines.skip(1).take(10).toList();
    final first = _splitCsvLine(lines.first, sep);
    final cols = first.length;
    var bestCol = 0;
    var bestHits = 0;
    for (var c = 0; c < cols; c++) {
      if (c == dateIdx || c == descIdx) continue;
      var hits = 0;
      for (final raw in sample) {
        final row = _splitCsvLine(raw, sep);
        if (c >= row.length) continue;
        final v = _parseDecimalFlexible(row[c].trim());
        if (v != null && v != 0) hits++;
      }
      if (hits > bestHits) {
        bestHits = hits;
        bestCol = c;
      }
    }
    return bestHits >= 2 ? bestCol : null;
  }

  /// Chave para detetar linhas repetidas (mesmo dia, valor e descrição normalizada).
  static String duplicateFingerprint(BankNotificationParseResult r) {
    final d = (r.descricao ?? '').toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final day = r.data == null
        ? 'nd'
        : '${r.data!.year}-${r.data!.month.toString().padLeft(2, '0')}-${r.data!.day.toString().padLeft(2, '0')}';
    final v = r.valor == null ? '' : r.valor!.toStringAsFixed(2);
    return '$day|$v|$d';
  }

  /// Aceita `R$ 50`, `r$ 1.000,00`, `R$50,5` (centavos opcionais).
  static final RegExp _reValor = RegExp(
    r'R\$\s*([\d]{1,3}(?:\.\d{3})*(?:,\d{1,2})?|\d+,\d{1,2}|\d{1,9})',
    caseSensitive: false,
  );
  static final RegExp _reData = RegExp(r'(\d{2}/\d{2}/\d{4})');

  /// Palavras que indicam entrada de dinheiro.
  static final List<RegExp> _incomeHints = [
    RegExp(r'PIX\s+RECEBIDO', caseSensitive: false),
    RegExp(r'PIX\s+RECEB', caseSensitive: false), // «pix recebido», bancos
    RegExp(r'PIX\s+.*CREDITAD', caseSensitive: false),
    RegExp(r'CREDITO\s+(?:DE\s+)?PIX', caseSensitive: false),
    RegExp(r'\bRECEBI\b', caseSensitive: false), // digitação: «recebi pix 400» / «recebi salário»
    RegExp(r'RECEBID[OA]\b', caseSensitive: false), // salário recebido, bônus recebido
    RegExp(r'CR[ÉE]DITO\s+(?:EM|NA)\s+CONTA', caseSensitive: false),
    RegExp(r'\bSAL[ÁA]RIO\s+RECEB', caseSensitive: false),
    RegExp(r'RECEB[OA]\s+.*SAL[ÁA]RIO', caseSensitive: false),
    RegExp(r'\bCOMISS[AÃ]O\s+RECEB', caseSensitive: false),
    RegExp(r'RECEB[OA].*COMISS', caseSensitive: false),
    RegExp(r'\bB[ÔO]NUS\s+RECEB', caseSensitive: false),
    RegExp(r'\bGRATIF\w*', caseSensitive: false), // gratificação
    RegExp(r'\bPR[ÓO]LAB\w*', caseSensitive: false), // pró-labore
    RegExp(r'TED\s+.*?(?:CREDIT|RECEB)', caseSensitive: false),
    RegExp(r'DEPOSITO\s+', caseSensitive: false),
    RegExp(r'TRANSFERENCIA\s+RECEB', caseSensitive: false),
    RegExp(r'RENDIMENTO', caseSensitive: false),
  ];

  /// Palavras que indicam saída.
  static final List<RegExp> _expenseHints = [
    RegExp(r'\bPAGUEI\b', caseSensitive: false), // «paguei conta X» (não confundir com receita)
    RegExp(r'COMPRA\s+APROVAD', caseSensitive: false),
    RegExp(r'COMPRA\s+(?:NO\s+)?DEBITO', caseSensitive: false),
    RegExp(r'COMPRA\s+NO\s+CART', caseSensitive: false),
    RegExp(r'DEBITO\s+', caseSensitive: false),
    RegExp(r'PAGAMENTO\s+(?:EFETUADO|APROVAD)', caseSensitive: false),
    RegExp(r'SAQUE\s+', caseSensitive: false),
    RegExp(r'TARIFA', caseSensitive: false),
  ];

  static DateTime _addCalendarMonths(DateTime d, int monthsToAdd) {
    if (monthsToAdd == 0) return d;
    final m0 = d.month - 1 + monthsToAdd;
    final y = d.year + m0 ~/ 12;
    final m = m0 % 12 + 1;
    final lastDay = DateTime(y, m + 1, 0).day;
    final day = d.day.clamp(1, lastDay);
    return DateTime(y, m, day, d.hour, d.minute, d.second);
  }

  static int _maxParcelasSmart() => AppBusinessRules.maxInstallments;

  static int? _detectParcelaCountPt(String lower) {
    if (RegExp(r'\bcada\s+parcela\b|\bpor\s+parcela\b|\bvalor\s+de\s+cada\b', caseSensitive: false).hasMatch(lower)) {
      return null;
    }
    final maxN = _maxParcelasSmart();
    final mNDe = RegExp(r'\b(\d{1,3})\s+parcelas?\s+de\b', caseSensitive: false).firstMatch(lower);
    if (mNDe != null) {
      final n = int.tryParse(mNDe.group(1)!);
      if (n != null && n >= 2 && n <= maxN) return n;
    }
    final mXDe = RegExp(r'\b(\d{1,3})\s*x\s+de\s+(?:r\$\s*)?[\d.,]+', caseSensitive: false).firstMatch(lower);
    if (mXDe != null) {
      final n = int.tryParse(mXDe.group(1)!);
      if (n != null && n >= 2 && n <= maxN) return n;
    }
    final mTotEm = RegExp(
      r'(?:valor\s+total\s+parcelad[oa]?|total\s+parcelad[oa]?)\s+em\s+(\d{1,3})\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (mTotEm != null) {
      final n = int.tryParse(mTotEm.group(1)!);
      if (n != null && n >= 2 && n <= maxN) return n;
    }
    final mEm = RegExp(r'\bem\s+(\d{1,3})\s+parcelas\b', caseSensitive: false).firstMatch(lower);
    if (mEm != null) {
      final n = int.tryParse(mEm.group(1)!);
      if (n != null && n >= 2 && n <= maxN) return n;
    }
    final mDiv = RegExp(r'\bdividido\s+em\s+(\d{1,3})\s*(?:parcelas|vezes)?\b', caseSensitive: false).firstMatch(lower);
    if (mDiv != null) {
      final n = int.tryParse(mDiv.group(1)!);
      if (n != null && n >= 2 && n <= maxN) return n;
    }
    final mWx = RegExp(r'\b(\d{1,3})\s*x\s*sem\s+juros\b', caseSensitive: false).firstMatch(lower);
    if (mWx != null) {
      final n = int.tryParse(mWx.group(1)!);
      if (n != null && n >= 2 && n <= maxN) return n;
    }
    final mPal = RegExp(
      r'\bem\s+(duas?|dois|tres|três|quatro|cinco|seis|sete|oito|nove|dez|onze|doze)\s+parcelas\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (mPal != null) {
      const map = {
        'duas': 2,
        'dua': 2,
        'dois': 2,
        'tres': 3,
        'três': 3,
        'quatro': 4,
        'cinco': 5,
        'seis': 6,
        'sete': 7,
        'oito': 8,
        'nove': 9,
        'dez': 10,
        'onze': 11,
        'doze': 12,
      };
      final key = mPal.group(1)!.toLowerCase();
      final v0 = map[key];
      if (v0 != null && v0 >= 2 && v0 <= maxN) return v0;
    }
    final mParcVez = RegExp(r'\bparcelad[oa]?\s+em\s+(\d{1,3})\s+vezes\b', caseSensitive: false).firstMatch(lower);
    if (mParcVez != null) {
      final n = int.tryParse(mParcVez.group(1)!);
      if (n != null && n >= 2 && n <= maxN) return n;
    }
    final mEmVezes = RegExp(r'\bem\s+(\d{1,3})\s+vezes\b', caseSensitive: false).firstMatch(lower);
    if (mEmVezes != null) {
      final n = int.tryParse(mEmVezes.group(1)!);
      if (n != null && n >= 2 && n <= maxN) return n;
    }
    // «6x 250», «6× de 250,00» (sem «de» obrigatório após o x).
    final mNxVal = RegExp(
      r'\b(\d{1,3})\s*[x×]\s*(?:de\s+)?(?:r\$\s*)?(\d{1,3}(?:\.\d{3})*,\d{1,2}|\d+,\d{1,2}|\d{1,7})\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (mNxVal != null) {
      final n = int.tryParse(mNxVal.group(1)!);
      if (n != null && n >= 2 && n <= maxN) return n;
    }
    final mNxInt = RegExp(
      r'\b(\d{1,3})\s*[x×]\s+(\d{1,3}(?:\.\d{3})*|\d{1,7})\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (mNxInt != null) {
      final n = int.tryParse(mNxInt.group(1)!);
      if (n != null && n >= 2 && n <= maxN) return n;
    }
    return null;
  }

  /// Valor de **cada** parcela em expressões do tipo «10 parcelas de 250,00» (não confundir com total).
  static double? _perParcelaReaisFromText(String lower, int n) {
    if (n < 2) return null;
    final m = RegExp(
      r'^\D*?(\d{1,3})\s+parcelas?\s+de\s*(?:r\$\s*)?(\d{1,3}(?:\.\d{3})*,\d{1,2}|\d+,\d{1,2}|\d{1,7})\b',
      caseSensitive: false,
    ).firstMatch(lower.trim());
    if (m != null) {
      final n1 = int.tryParse(m.group(1)!);
      if (n1 == n) {
        final raw = m.group(2)!;
        final v = _parseBrDecimal(raw) ?? _parseDecimalFlexible(raw);
        if (v != null && v > 0) return v;
      }
    }
    final m2 = RegExp(
      r'^\D*?(\d{1,3})\s*x\s+de\s*(?:r\$\s*)?(\d{1,3}(?:\.\d{3})*,\d{1,2}|\d+,\d{1,2}|\d{1,7})',
      caseSensitive: false,
    ).firstMatch(lower.trim());
    if (m2 != null) {
      final n1 = int.tryParse(m2.group(1)!);
      if (n1 == n) {
        final raw = m2.group(2)!;
        final v = _parseBrDecimal(raw) ?? _parseDecimalFlexible(raw);
        if (v != null && v > 0) return v;
      }
    }
    final m3 = RegExp(
      r'\b(\d{1,3})\s*[x×]\s*(?:de\s+)?(?:r\$\s*)?(\d{1,3}(?:\.\d{3})*,\d{1,2}|\d+,\d{1,2}|\d{1,7})\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (m3 != null) {
      final n1 = int.tryParse(m3.group(1)!);
      if (n1 == n) {
        final raw = m3.group(2)!;
        final v = _parseBrDecimal(raw) ?? _parseDecimalFlexible(raw);
        if (v != null && v > 0) return v;
      }
    }
    final m4 = RegExp(
      r'\b(\d{1,3})\s*[x×]\s+(\d{1,3}(?:\.\d{3})*|\d{1,7})\b',
      caseSensitive: false,
    ).firstMatch(lower);
    if (m4 != null) {
      final n1 = int.tryParse(m4.group(1)!);
      if (n1 == n) {
        final raw = m4.group(2)!;
        final v = _parseBrDecimal(raw) ?? _parseDecimalFlexible(raw) ?? double.tryParse(raw.replaceAll('.', ''));
        if (v != null && v > 0) return v;
      }
    }
    return null;
  }

  /// [baseValor] = valor principal inferido (ex. valor de cada parcela se o texto o diz explicitamente).
  static double? _perParcelaReaisFromTextWithBase(String lower, int n, double? baseValor) {
    final a = _perParcelaReaisFromText(lower, n);
    if (a != null) return a;
    if (baseValor == null || baseValor <= 0) return null;
    if (RegExp(r'\bvalor\s+de\s+cada\s+parcela', caseSensitive: false).hasMatch(lower)) {
      return baseValor;
    }
    final mm = RegExp(
      r'\bcada\s+parcela\s+(?:r\$\s*)?(\d{1,3}(?:\.\d{3})*,\d{1,2}|\d+,\d{1,2}|\d{1,7})',
      caseSensitive: false,
    ).firstMatch(lower);
    if (mm != null) {
      final v = _parseBrDecimal(mm.group(1)!) ?? _parseDecimalFlexible(mm.group(1)!);
      if (v != null && v > 0) return v;
    }
    return null;
  }

  static DateTime? _parsePrimeiroVencimentoPt(String lower) {
    final reComeca = RegExp(
      r'(?:começando\s+em|comecando\s+em|inicio\s+em|início\s+em|venc(?:imento)?\s*(?:inicial)?)\s*[:\s]*(\d{2}/\d{2}(?:/\d{4})?)',
      caseSensitive: false,
    );
    final mc = reComeca.firstMatch(lower);
    if (mc != null) {
      final cap = mc.group(1)!;
      if (cap.length == 5) {
        final y = DateTime.now().year;
        return _parseDataBr('$cap/$y');
      }
      return _parseDataBr(cap);
    }
    final re = RegExp(
      r'(?:primeir[oa]|1\.?\s*[ªa]\s*parcela|primeiro\s+vencimento)\s*[:\s]*(\d{2}/\d{2}(?:/\d{4})?)',
      caseSensitive: false,
    );
    final m = re.firstMatch(lower);
    if (m == null) return null;
    final cap = m.group(1)!;
    if (cap.length == 5) {
      final y = DateTime.now().year;
      return _parseDataBr('$cap/$y');
    }
    return _parseDataBr(cap);
  }

  static String _stripParcelaBoilerplatePt(String desc) {
    var s = desc.trim();
    s = s.replaceAll(
      RegExp(r'^\d{1,3}\s+parcelas?\s+de\s*(?:r\$\s*)?[\d.,]+\s*', caseSensitive: false),
      '',
    );
    s = s.replaceAll(
      RegExp(r'^\d{1,3}\s*x\s+de\s*(?:r\$\s*)?[\d.,]+\s*', caseSensitive: false),
      '',
    );
    s = s.replaceAll(
      RegExp(r'^\d{1,3}\s*[x×]\s*(?:de\s+)?(?:r\$\s*)?[\d.,]+\s*', caseSensitive: false),
      '',
    );
    s = s.replaceAll(
      RegExp(r'\s+\d{1,3}\s*[x×]\s*(?:de\s+)?(?:r\$\s*)?[\d.,]+.*$', caseSensitive: false),
      '',
    );
    s = s.replaceAll(
      RegExp(r'\s*em\s+(?:\d{1,3}|duas?|dois|tres|três|quatro|cinco|seis|sete|oito|nove|dez|onze|doze)\s+parcelas.*$', caseSensitive: false),
      '',
    );
    s = s.replaceAll(
      RegExp(r'\s*parcelad[oa]?\s+em\s+\d{1,2}\s+vezes.*$', caseSensitive: false),
      '',
    );
    s = s.replaceAll(
      RegExp(r'\s*em\s+\d{1,2}\s+vezes.*$', caseSensitive: false),
      '',
    );
    s = s.replaceAll(RegExp(r'\s*valor\s+total\b.*$', caseSensitive: false), '');
    s = s.replaceAll(
      RegExp(r'\s*(?:primeir[oa]|1\.?\s*[ªa]\s*parcela|primeiro\s+vencimento)\s*[:\s]*\d{2}/\d{2}(?:/\d{4})?.*$', caseSensitive: false),
      '',
    );
    s = s.replaceAll(
      RegExp(
        r'\s*(?:começando\s+em|comecando\s+em|inicio\s+em|início\s+em)\s*[:\s]*\d{2}/\d{2}(?:/\d{4})?.*$',
        caseSensitive: false,
      ),
      '',
    );
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (RegExp(r'^reais\s+', caseSensitive: false).hasMatch(s)) {
      s = s.replaceFirst(RegExp(r'^reais\s+', caseSensitive: false), '');
    }
    return s.trim();
  }

  /// Divide um único parse (valor total) em N lançamentos quando o texto menciona parcelas (ex.: «em duas parcelas»).
  static List<BankNotificationParseResult> _expandInstallmentsFromText(String sourceText, BankNotificationParseResult base) {
    if (!base.hasMinimumForConfirmation) return [base];
    final lower = sourceText.toLowerCase();
    final n = _detectParcelaCountPt(lower);
    if (n == null || n < 2) return [base];

    final perEach = _perParcelaReaisFromTextWithBase(lower, n, base.valor);
    final int totalCents;
    if (perEach != null) {
      totalCents = (perEach * 100).round();
      if (totalCents < 1) return [base];
    } else {
      final total = base.valor!;
      totalCents = (total * 100).round();
      if (totalCents < n) return [base];
    }

    final firstDue = _parsePrimeiroVencimentoPt(lower) ?? base.data ?? DateTime.now();
    final baseDesc = (base.descricao ?? '').trim();
    final descCore = _stripParcelaBoilerplatePt(baseDesc);
    final labelBase = descCore.isNotEmpty ? descCore : baseDesc;

    final baseSnippet = sourceText.length > 380 ? sourceText.substring(0, 380) : sourceText;
    final out = <BankNotificationParseResult>[];
    for (var i = 0; i < n; i++) {
      final double v;
      if (perEach != null) {
        v = perEach;
      } else {
        final each = totalCents ~/ n;
        final rem = totalCents % n;
        final cents = each + (i < rem ? 1 : 0);
        v = cents / 100.0;
      }
      final dt = _addCalendarMonths(firstDue, i);
      final label = '$labelBase (${i + 1}/$n)';
      final snip = '$baseSnippet · p${i + 1}/$n';
      out.add(
        base.copyWith(
          valor: v,
          data: dt,
          descricao: label,
          rawSnippet: snip,
        ),
      );
    }
    return out;
  }

  /// Vários SMS, blocos separados por linha em branco, ou mensagens coladas
  /// (ex.: vários «BRADESCO CARTOES:» seguidos), mais linhas em formato livre
  /// (`supermercado 100`, `13/04/2026 farmácia 20,00`).
  static List<BankNotificationParseResult> parseManyForBatch(String texto) {
    var t = texto.trim();
    if (t.isEmpty) return const [];
    if (t.length > kMaxParseInputChars) {
      t = t.substring(0, kMaxParseInputChars);
    }
    final sliced = sliceToFaturaLancamentosSection(t);
    if (sliced.trim().isNotEmpty) {
      t = sliced.length > kMaxParseInputChars ? sliced.substring(0, kMaxParseInputChars) : sliced;
    }

    final out = <BankNotificationParseResult>[];

    void addFromBlock(String block) {
      final trimmed = block.trim();
      if (trimmed.isEmpty) return;
      final bankParts = _splitMultipleBankMessages(trimmed);
      if (bankParts.length > 1) {
        for (final b in bankParts) {
          final r = parse(b);
          if (r.hasMinimumForConfirmation) {
            out.addAll(_expandInstallmentsFromText(b, r));
          }
        }
        return;
      }
      final linesRaw = trimmed.split(RegExp(r'[\r\n]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final lines = _mergeWrappedFaturaLines(linesRaw);
      if (lines.length > 1) {
        final bankish = lines.where(_looksLikeStandaloneBankLine).length;
        if (bankish >= 2) {
          for (final L in lines) {
            var r = parse(L);
            if (!r.hasMinimumForConfirmation) {
              final fat = _tryFaturaCardStatementLine(L);
              if (fat != null) {
                r = fat;
              } else {
                final multi = _tryFreeformCompositeLine(L);
                if (multi != null) {
                  for (final c in multi) {
                    if (c.hasMinimumForConfirmation) {
                      out.addAll(_expandInstallmentsFromText(c.rawSnippet, c));
                    }
                  }
                  continue;
                }
                final f = _tryFreeformLine(L);
                if (f != null) r = f;
              }
            }
            if (r.hasMinimumForConfirmation) {
              out.addAll(_expandInstallmentsFromText(L, r));
            }
          }
          return;
        }
      }
      // Uma linha: vários itens com | ou vírgula («mercado 10,00 | farmácia 150,00» ou com vírgulas, sem partir 1.234,56)
      // têm de ser resolvidos *antes* de [parse] no texto completo, senão ganha só o 1.º/último bloco.
      var workForLine = trimmed;
      if (lines.length == 1) {
        workForLine = _normalizeListLikePastedLine(lines.first);
        if (RegExp(r'[,;|]').hasMatch(workForLine)) {
          final multiFirst = _tryFreeformCompositeLine(workForLine);
          if (multiFirst != null && multiFirst.length >= 2) {
            for (final c in multiFirst) {
              if (c.hasMinimumForConfirmation) {
                out.addAll(_expandInstallmentsFromText(c.rawSnippet, c));
              }
            }
            return;
          }
        }
      }
      final whole = parse(workForLine);
      if (whole.hasMinimumForConfirmation) {
        out.addAll(_expandInstallmentsFromText(workForLine, whole));
        return;
      }
      final linesToParse = lines.length == 1 ? <String>[workForLine] : lines;
      for (final line in linesToParse) {
        final L = line.trim();
        if (L.isEmpty) continue;
        var r = parse(L);
        if (!r.hasMinimumForConfirmation) {
          final fat = _tryFaturaCardStatementLine(L);
          if (fat != null) {
            r = fat;
          } else {
            final multi = _tryFreeformCompositeLine(L);
            if (multi != null) {
              for (final c in multi) {
                if (c.hasMinimumForConfirmation) {
                  out.addAll(_expandInstallmentsFromText(c.rawSnippet, c));
                }
              }
              continue;
            }
            final f = _tryFreeformLine(L);
            if (f != null) r = f;
          }
        }
        if (r.hasMinimumForConfirmation) {
          out.addAll(_expandInstallmentsFromText(L, r));
        }
      }
    }

    final paragraphs = t.split(RegExp(r'\n\s*\n')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (paragraphs.isEmpty) {
      addFromBlock(t);
    } else {
      for (final p in paragraphs) {
        addFromBlock(p);
      }
    }

    List<BankNotificationParseResult> mapped = out;
    if (out.length > kMaxBatchParseRows) {
      mapped = out.sublist(0, kMaxBatchParseRows);
    }
    return mapped.map(_sanitizeDescInResult).toList();
  }

  static final RegExp _reFaturaDateStart = RegExp(r'^\d{2}/\d{2}(?:/\d{4})?\b');
  static final RegExp _reMoneyTokenNearEnd = RegExp(
    r'(?:R\$\s*)?(?:\d{1,3}(?:\.\d{3})*,\d{2}|\d{1,3},\d{2}|\d{1,3}(?:\.\d{3})*|\d+)\s*-?\s*$',
    caseSensitive: false,
  );

  /// Alguns PDFs quebram uma compra em 2-3 linhas:
  /// `01/03 RESTAURANTE XYZ` + `CIDADE` + `3,50`.
  /// Este merge recompõe uma linha única para o parser de fatura.
  static List<String> _mergeWrappedFaturaLines(List<String> lines) {
    if (lines.length < 2) return lines;
    final out = <String>[];
    var i = 0;
    while (i < lines.length) {
      final cur = lines[i].trim();
      if (_reFaturaDateStart.hasMatch(cur) && !_reMoneyTokenNearEnd.hasMatch(cur)) {
        var merged = cur;
        var j = i + 1;
        var hops = 0;
        while (j < lines.length && hops < 2) {
          final nxt = lines[j].trim();
          if (nxt.isEmpty) {
            j++;
            continue;
          }
          if (_reFaturaDateStart.hasMatch(nxt) && _reMoneyTokenNearEnd.hasMatch(nxt)) {
            break;
          }
          merged = '$merged $nxt';
          hops++;
          j++;
          if (_reMoneyTokenNearEnd.hasMatch(merged)) break;
        }
        out.add(merged.trim());
        i = j;
        continue;
      }
      out.add(cur);
      i++;
    }
    return out;
  }

  static BankNotificationParseResult _sanitizeDescInResult(BankNotificationParseResult r) {
    final d = r.descricao;
    if (d == null || d.trim().isEmpty) return r;
    final s = OcrDescriptionSanity.sanitize(d);
    if (s == d) return r;
    return r.copyWith(descricao: s);
  }

  /// Recorta texto de fatura (PDF ou cópia) à zona **Lançamentos** / tabela de movimentos; ignora capa, limites e resumo.
  /// Útil também quando o utilizador cola só o print da tabela (sem título).
  static String sliceToFaturaLancamentosSection(String fullText) {
    final t = fullText.replaceAll('\r', '\n');
    if (t.trim().isEmpty) return t;

    final lower = t.toLowerCase();
    var best = -1;

    // Ordem: frases mais específicas da fatura de cartão; depois genéricos (evita cortar em "compras" solto no meio do PDF).
    const startMarkers = [
      'histórico de lançamentos',
      'historico de lancamentos',
      'lançamentos da fatura',
      'lancamentos da fatura',
      'demonstrativo de compras',
      'detalhamento de lançamentos',
      'detalhamento dos lançamentos',
      'compras nacionais',
      'compras parceladas',
      'lançamentos',
      'lancamentos',
      'detalhamento',
    ];
    for (final m in startMarkers) {
      final i = lower.indexOf(m);
      if (i >= 0 && (best < 0 || i < best)) best = i;
    }

    // Só o print da tabela: primeira linha com data DD/MM (com ou sem ano) + texto
    if (best < 0) {
      final re = RegExp(r'^\s*(\d{2}/\d{2})(?:/\d{4})?\s+\S+', multiLine: true);
      final match = re.firstMatch(t);
      if (match != null) best = match.start;
    }

    var slice = best >= 0 ? t.substring(best) : t;

    final sLow = slice.toLowerCase();
    var end = slice.length;
    const stopMarkers = [
      'total da fatura',
      'totais da fatura',
      'total a pagar',
      'total geral',
      'resumo da fatura',
      'próxima fatura',
      'proxima fatura',
      'pagamento mínimo',
      'pagamento minimo',
      'limite total do cartão',
      'limite total',
      'limite disponível',
      'limite disponivel',
      'total de compras',
      'total das compras',
      'pagamento até',
      'pagamento ate',
      'débito automático',
      'debito automatico',
      'fatura anterior',
      'saldo em reais',
      'saldo em r\$',
      'outros encargos',
    ];
    for (final stop in stopMarkers) {
      final j = sLow.indexOf(stop);
      if (j >= 0 && j < end) end = j;
    }
    return slice.substring(0, end).trim();
  }

  /// Linha tipo fatura de cartão: `DD/MM … descrição … 159,90` ou `… 5,4400  54,40` (valor final em R$ é o último token BR).
  static BankNotificationParseResult? _tryFaturaCardStatementLine(String line) {
    var t = line.trim();
    if (t.length < 8) return null;
    final u = t.toUpperCase();
    if (u == 'DATA' || u == 'R\$' || u.startsWith('US\$') || u == 'COTAÇÃO' || u == 'COTACAO') return null;
    if (u.contains('HISTÓRICO') && u.contains('LANÇAMENT')) return null;
    if (u.contains('HISTORICO') && u.contains('LANCAMENT')) return null;

    // Crédito na fatura costuma vir como «4.718,00 -» (espaço antes do menos).
    t = t.replaceAll(RegExp(r'\s+-\s*$'), '').trimRight();
    if (t.endsWith('-')) {
      t = t.substring(0, t.length - 1).trimRight();
    }

    var toks = t.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toList();
    while (toks.isNotEmpty && toks.last == '-') {
      toks = toks.sublist(0, toks.length - 1);
    }
    if (toks.length < 3) return null;

    String? lastBrl;
    var cut = toks.length;
    for (var i = toks.length - 1; i >= 0; i--) {
      var tok = toks[i].trim();
      tok = tok.replaceFirst(RegExp(r'^(R\$)\s*', caseSensitive: false), '');
      if (tok.endsWith('-') && tok.length > 1) {
        tok = tok.substring(0, tok.length - 1).trim();
      }
      if (RegExp(r'^(?:\d{1,3}(?:\.\d{3})*,\d{2}|\d{1,3},\d{2}|\d+\.\d{2}|\d{1,3}(?:\.\d{3})*|\d+)$').hasMatch(tok)) {
        if (tok.contains('.') && !tok.contains(',')) {
          final onlyDotsAsThousands = RegExp(r'^\d{1,3}(?:\.\d{3})+$').hasMatch(tok);
          if (onlyDotsAsThousands) {
            tok = tok.replaceAll('.', '');
          } else {
            tok = tok.replaceAll('.', ',');
          }
        }
        lastBrl = tok;
        cut = i;
        break;
      }
    }
    if (lastBrl == null) return null;

    double? val;
    final intLike = RegExp(r'^\d{1,3}(?:\.\d{3})*$|^\d+$').hasMatch(lastBrl);
    if (intLike) {
      val = double.tryParse(lastBrl.replaceAll('.', ''));
    } else {
      val = _parseBrDecimal(lastBrl);
    }
    if (val == null || val <= 0) return null;

    final headToks = toks.sublist(0, cut);
    if (headToks.isEmpty) return null;
    final first = headToks.first;
    final dm4 = RegExp(r'^(\d{2}/\d{2}/\d{4})$').firstMatch(first);
    final dm2 = RegExp(r'^(\d{2}/\d{2})$').firstMatch(first);
    DateTime? dt;
    if (dm4 != null) {
      dt = _parseDataBr(dm4.group(1)!);
    } else if (dm2 != null) {
      final y = DateTime.now().year;
      dt = _parseDataBr('${dm2.group(1)!}/$y');
    } else {
      return null;
    }
    if (dt == null) return null;

    final desc = headToks.skip(1).join(' ').trim();
    if (desc.length < 2) return null;

    return BankNotificationParseResult(
      valor: val,
      data: dt,
      descricao: desc,
      type: _inferType('$desc $t'),
      suggestedPresetId: _suggestBankPreset(t),
      rawSnippet: line.length > 400 ? line.substring(0, 400) : line,
    );
  }

  /// Texto extraído de fatura PDF: limita à zona **Lançamentos** e devolve linhas como [BankNotificationParseResult].
  static List<BankNotificationParseResult> parseFromFaturaPdfPlainText(String fullText) {
    final slice = sliceToFaturaLancamentosSection(fullText);
    if (slice.trim().isEmpty) return const [];

    final results = <BankNotificationParseResult>[];
    for (final line in slice.split('\n')) {
      final L = line.trim();
      if (L.length < 8) continue;
      var r = parse(L);
      if (!r.hasMinimumForConfirmation) {
        BankNotificationParseResult? f = _tryFaturaCardStatementLine(L);
        if (f == null) {
          final multi = _tryFreeformCompositeLine(L);
          if (multi != null) {
            for (final c in multi) {
              if (c.hasMinimumForConfirmation) results.add(c);
            }
            continue;
          }
        }
        f ??= _tryFreeformLine(L);
        if (f != null) r = f;
      }
      if (r.hasMinimumForConfirmation) results.add(r);
    }
    if (results.length > kMaxBatchParseRows) {
      return results
          .sublist(0, kMaxBatchParseRows)
          .map(_sanitizeDescInResult)
          .toList();
    }
    return results.map(_sanitizeDescInResult).toList();
  }

  static bool _looksLikeStandaloneBankLine(String line) {
    if (!_reValor.hasMatch(line)) return false;
    final u = line.toUpperCase();
    return u.contains('BRADESCO') ||
        u.contains('ITAU') ||
        u.contains('ITAÚ') ||
        u.contains('SANTANDER') ||
        u.contains('NUBANK') ||
        u.contains('CAIXA') ||
        u.contains('COMPRA') ||
        u.contains('PIX') ||
        u.contains('SAQUE') ||
        u.contains('PAGAMENTO');
  }

  static List<String> _splitMultipleBankMessages(String s) {
    final re = RegExp(r'(?=\n\s*(?:BRADESCO\s+CARTOES?:|BRADESCO\s+CARTÕES?:|ITAU\b|ITAÚ\b|NUBANK\b|CAIXA\b|SANTANDER\b))', caseSensitive: false);
    var parts = s.split(re).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    if (parts.length > 1) return parts;
    final re2 = RegExp(r'(?=BRADESCO\s+CARTOES?:|BRADESCO\s+CARTÕES?:)', caseSensitive: false);
    parts = s.split(re2).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    return parts;
  }

  /// Corrige colagem «R$ R$»; não mexe em «8, 750» (código especial a jusante).
  static String _normalizeListLikePastedLine(String t) {
    return t.replaceAll(RegExp(r'R\$\s*R\$\s*', caseSensitive: false), r'R$ ').trim();
  }

  /// Vários lançamentos livres na mesma linha, separados por **|** (preferido), vírgula ou `;`, sem partir valores `1.234,56`.
  /// Ex.: `100 mercado | 157,80 farmacia` ou `100 mercado, 157,80 farmacia`.
  static List<BankNotificationParseResult>? _tryFreeformCompositeLine(String line) {
    final t = line.trim();
    if (t.length < 5) return null;
    if (_tryFaturaCardStatementLine(t) != null) return null;
    if (!RegExp(r'[,;|]').hasMatch(t)) return null;

    var parts = _splitFreeformCompositeParts(t);
    if (parts.length < 2) return null;

    parts = _mergeTrailingDescriptionOnlyParts(parts);

    final out = <BankNotificationParseResult>[];
    for (final seg in parts) {
      final r = _tryFreeformSegment(seg);
      if (r != null && r.hasMinimumForConfirmation) out.add(r);
    }
    return out.length >= 2 ? out : null;
  }

  static const String _kBrAmountPh = '\uE000';
  static const String _kBrAmountPhEnd = '\uE001';

  /// Campo Lançamento inteligente: converte **vírgulas** (ou `;`) **entre** itens em ` | `,
  /// com a mesma proteção de `1.234,56` que o parse. Assim o utilizador **não precisa** de teclar o pipe.
  static String? smartInputAutoPipesFromListCommas(String line) {
    final t = line.trim();
    if (t.isEmpty) return null;
    if (t.contains('|')) return null;
    if (!RegExp(r'[,;]').hasMatch(t)) return null;
    final parts = _splitFreeformCompositeParts(t);
    if (parts.length < 2) return null;
    return parts.join(' | ');
  }

  static List<String> _splitFreeformCompositeParts(String line) {
    // Ex.: «feira 89, 55» (vírgula+espaço no teclado) → «89,55» antes de máscar, sem capturar «8, 750» (75+0).
    var pre = line.replaceAllMapped(
      RegExp(r'\b(\d{1,3}(?:\.\d{3})*),\s*(\d{2})(?![0-9])'),
      (m) => '${m[1]},${m[2]}',
    );
    final amounts = <String>[];
    var masked = pre.replaceAllMapped(
      RegExp(r'\d{1,3}(?:\.\d{3})*,\d{2}\b'),
      (m) {
        amounts.add(m.group(0)!);
        return '$_kBrAmountPh${amounts.length - 1}$_kBrAmountPhEnd';
      },
    );
    return masked
        .split(RegExp(r'\s*[,;|]\s*'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((e) {
          var s = e;
          for (var i = 0; i < amounts.length; i++) {
            s = s.replaceAll('$_kBrAmountPh$i$_kBrAmountPhEnd', amounts[i]);
          }
          return s;
        })
        .toList();
  }

  /// Junta à entrada anterior fragmentos sem valor (ex.: `237,50 , no banco bradesco`).
  static List<String> _mergeTrailingDescriptionOnlyParts(List<String> parts) {
    final out = <String>[];
    for (final p in parts) {
      final pt = p.trim();
      if (pt.isEmpty) continue;
      if (out.isEmpty) {
        out.add(pt);
        continue;
      }
      final solo = _tryFreeformSegment(pt);
      if (solo != null && solo.hasMinimumForConfirmation) {
        out.add(pt);
      } else {
        out[out.length - 1] = '${out.last}, $pt';
      }
    }
    return out;
  }

  /// Um único lançamento livre (valor antes ou depois da descrição, com ou sem data).
  static BankNotificationParseResult? _tryFreeformSegment(String t0) {
    final t = t0.trim();
    if (t.isEmpty) return null;

    var m = RegExp(
      r'^(\d{2}/\d{2}/\d{4})\s+(.+?)\s+((?:\d{1,3}(?:\.\d{3})*|\d+),\d{2})\s*(?:reais?|R\$\s*)?\s*$',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      final val = _parseBrDecimal(m.group(3)!);
      final dt = _parseDataBr(m.group(1)!);
      if (val != null && val > 0) {
        final desc = m.group(2)!.trim();
        return BankNotificationParseResult(
          valor: val,
          data: dt,
          descricao: desc,
          type: _inferType('$desc $t'),
          suggestedPresetId: _suggestBankPreset(t),
          rawSnippet: t.length > 400 ? t.substring(0, 400) : t,
        );
      }
    }

    m = RegExp(
      r'^(\d{2}/\d{2})\s+(.+?)\s+((?:\d{1,3}(?:\.\d{3})*|\d+),\d{2})\s*$',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      final y = DateTime.now().year;
      final dmy = '${m.group(1)!}/$y';
      final val = _parseBrDecimal(m.group(3)!);
      final dt = _parseDataBr(dmy);
      if (val != null && val > 0) {
        final desc = m.group(2)!.trim();
        return BankNotificationParseResult(
          valor: val,
          data: dt,
          descricao: desc,
          type: _inferType('$desc $t'),
          suggestedPresetId: _suggestBankPreset(t),
          rawSnippet: t.length > 400 ? t.substring(0, 400) : t,
        );
      }
    }

    // Linguagem natural: «compra supermercado 100 reais» / «gasto farmácia 50».
    m = RegExp(
      r'^(?:compra|comprei|gasto|gastei|pagamento|paguei|despesa)\s+(.+?)\s+(?:r\$\s*)?(\d{1,6})(?:\s+reais?)?\s*$',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      final val = int.tryParse(m.group(2)!);
      final desc0 = m.group(1)!.trim();
      if (val != null && val >= 1 && val < 10000000 && desc0.length >= 2) {
        final desc = polishSmartPasteDescription(desc0) ?? desc0;
        return BankNotificationParseResult(
          valor: val.toDouble(),
          data: DateTime.now(),
          descricao: desc,
          type: _inferType('$desc $t'),
          suggestedPresetId: _suggestBankPreset(t),
          rawSnippet: t.length > 400 ? t.substring(0, 400) : t,
        );
      }
    }

    m = RegExp(
      r'^(.+?)\s+(?:r\$\s*)?(\d{1,6})\s+reais?\s*$',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      final val = int.tryParse(m.group(2)!);
      var desc0 = m.group(1)!.trim();
      if (val != null && val >= 1 && val < 10000000 && desc0.length >= 2) {
        if (!RegExp(r'^(r\$|reais?)$', caseSensitive: false).hasMatch(desc0)) {
          final desc = polishSmartPasteDescription(desc0) ?? desc0;
          return BankNotificationParseResult(
            valor: val.toDouble(),
            data: DateTime.now(),
            descricao: desc,
            type: _inferType('$desc $t'),
            suggestedPresetId: _suggestBankPreset(t),
            rawSnippet: t.length > 400 ? t.substring(0, 400) : t,
          );
        }
      }
    }

    // Valor com centavos (BR) antes do texto: `157,80 farmacia`
    m = RegExp(
      r'^(\d{1,3}(?:\.\d{3})*,\d{2})\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      final val = _parseBrDecimal(m.group(1)!);
      final desc = m.group(2)!.trim();
      if (val != null && val > 0 && desc.length >= 2) {
        DateTime? dt;
        final dm = _reData.firstMatch(desc);
        if (dm != null) {
          dt = _parseDataBr(dm.group(1)!);
        }
        dt ??= DateTime.now();
        return BankNotificationParseResult(
          valor: val,
          data: dt,
          descricao: desc,
          type: _inferType('$desc $t'),
          suggestedPresetId: _suggestBankPreset(t),
          rawSnippet: t.length > 400 ? t.substring(0, 400) : t,
        );
      }
    }

    // Total com «de R$ N» (ou de N) + «parcelado em M vezes» (ex.: geladeira de 1200 parcelado em 6 vezes).
    m = RegExp(
      r'^(.+?)\s+de\s+(?:r\$\s*)?(\d{1,3}(?:\.\d{3})*(?:,\d{1,2})?|\d+,\d{1,2}|\d{1,7})\s+parcelad[oa]?\s+em\s+(\d{1,3})\s+vezes',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      final desc0 = m.group(1)!.trim();
      final val = _parseBrDecimal(m.group(2)!) ?? _parseDecimalFlexible(m.group(2)!);
      if (val != null && val > 0 && desc0.length >= 2) {
        return BankNotificationParseResult(
          valor: val,
          data: DateTime.now(),
          descricao: desc0,
          type: _inferType('$desc0 $t'),
          suggestedPresetId: _suggestBankPreset(t),
          rawSnippet: t.length > 400 ? t.substring(0, 400) : t,
        );
      }
    }

    // Descrição + valor (sem «de») + «parcelado em M vezes» (ex.: geladeira 1200 parcelado em 6 vezes).
    m = RegExp(
      r'^(.+?)\s+(\d{1,3}(?:\.\d{3})*(?:,\d{1,2})?|\d+,\d{1,2}|\d{1,7})\s+parcelad[oa]?\s+em\s+(\d{1,3})\s+vezes',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      final desc0 = m.group(1)!.trim();
      final val = _parseBrDecimal(m.group(2)!) ?? _parseDecimalFlexible(m.group(2)!);
      if (val != null && val > 0 && desc0.length >= 2) {
        if (!RegExp(r'^(r\$|reais?)$', caseSensitive: false).hasMatch(desc0)) {
          return BankNotificationParseResult(
            valor: val,
            data: DateTime.now(),
            descricao: desc0,
            type: _inferType('$desc0 $t'),
            suggestedPresetId: _suggestBankPreset(t),
            rawSnippet: t.length > 400 ? t.substring(0, 400) : t,
          );
        }
      }
    }

    // Total com «de VALOR» + «em M parcelas» (ex.: geladeira de 1200 em 6 parcelas).
    m = RegExp(
      r'^(.+?)\s+de\s+(?:r\$\s*)?(\d{1,3}(?:\.\d{3})*(?:,\d{1,2})?|\d+,\d{1,2}|\d{1,7})\s+em\s+(\d{1,3})\s+parcelas?\b',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      final desc0 = m.group(1)!.trim();
      final val = _parseBrDecimal(m.group(2)!) ?? _parseDecimalFlexible(m.group(2)!);
      if (val != null && val > 0 && desc0.length >= 2) {
        return BankNotificationParseResult(
          valor: val,
          data: DateTime.now(),
          descricao: desc0,
          type: _inferType('$desc0 $t'),
          suggestedPresetId: _suggestBankPreset(t),
          rawSnippet: t.length > 400 ? t.substring(0, 400) : t,
        );
      }
    }

    // Descrição + total + «em M parcelas» sem «de» (ex.: geladeira 1200 em 6 parcelas).
    m = RegExp(
      r'^(.+?)\s+(\d{1,3}(?:\.\d{3})*(?:,\d{1,2})?|\d+,\d{1,2}|\d{1,7})\s+em\s+(\d{1,3})\s+parcelas?\b',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      final desc0 = m.group(1)!.trim();
      final val = _parseBrDecimal(m.group(2)!) ?? _parseDecimalFlexible(m.group(2)!);
      if (val != null && val > 0 && desc0.length >= 2) {
        if (!RegExp(r'^(r\$|reais?)$', caseSensitive: false).hasMatch(desc0)) {
          return BankNotificationParseResult(
            valor: val,
            data: DateTime.now(),
            descricao: desc0,
            type: _inferType('$desc0 $t'),
            suggestedPresetId: _suggestBankPreset(t),
            rawSnippet: t.length > 400 ? t.substring(0, 400) : t,
          );
        }
      }
    }

    // Valor inteiro antes do texto: `100 mercado` (evita ano isolado).
    m = RegExp(r'^(\d{1,6})\s+(.+)$').firstMatch(t);
    if (m != null) {
      final n = int.tryParse(m.group(1)!);
      var desc = m.group(2)!.trim();
      if (n != null && n >= 1 && n < 10000000 && desc.length >= 2) {
        if (n >= 2000 && n <= 2035 && desc.length < 4) {
          // provável ano
        } else {
          final val = n.toDouble();
          DateTime? dt;
          final dm = _reData.firstMatch(desc);
          if (dm != null) {
            dt = _parseDataBr(dm.group(1)!);
            desc = desc.replaceFirst(dm.group(0)!, '').trim();
          }
          dt ??= DateTime.now();
          return BankNotificationParseResult(
            valor: val,
            data: dt,
            descricao: desc,
            type: _inferType('$desc $t'),
            suggestedPresetId: _suggestBankPreset(t),
            rawSnippet: t.length > 400 ? t.substring(0, 400) : t,
          );
        }
      }
    }

    m = RegExp(
      r'^(.+?)\s+((?:\d{1,3}(?:\.\d{3})*|\d+),\d{2})\s*(?:reais?|R\$\s*)?\s*$',
      caseSensitive: false,
    ).firstMatch(t);
    if (m != null) {
      final val = _parseBrDecimal(m.group(2)!);
      if (val != null && val > 0) {
        var desc = m.group(1)!.trim();
        DateTime? dt;
        final dm = _reData.firstMatch(desc);
        if (dm != null) {
          dt = _parseDataBr(dm.group(1)!);
          desc = desc.replaceFirst(dm.group(0)!, '').trim();
        }
        dt ??= DateTime.now();
        if (desc.length < 2) return null;
        return BankNotificationParseResult(
          valor: val,
          data: dt,
          descricao: desc,
          type: _inferType('$desc $t'),
          suggestedPresetId: _suggestBankPreset(t),
          rawSnippet: t.length > 400 ? t.substring(0, 400) : t,
        );
      }
    }

    // Descrição … valor com centavos … texto extra (ex.: `… 237,50 , no banco`)
    final allBr = RegExp(r'\d{1,3}(?:\.\d{3})*,\d{2}').allMatches(t).toList();
    if (allBr.isNotEmpty) {
      final last = allBr.last;
      final val = _parseBrDecimal(last.group(0)!);
      if (val != null && val > 0) {
        var bef = t.substring(0, last.start).trim();
        var aft = t.substring(last.end).trim();
        if (aft.startsWith(',')) aft = aft.substring(1).trim();
        var desc = bef;
        if (aft.isNotEmpty) desc = '$desc, $aft'.trim();
        if (desc.length >= 2) {
          DateTime? dt;
          final dm = _reData.firstMatch(desc);
          if (dm != null) {
            dt = _parseDataBr(dm.group(1)!);
            desc = desc.replaceFirst(dm.group(0)!, '').trim();
          }
          dt ??= DateTime.now();
          return BankNotificationParseResult(
            valor: val,
            data: dt,
            descricao: desc,
            type: _inferType('$desc $t'),
            suggestedPresetId: _suggestBankPreset(t),
            rawSnippet: t.length > 400 ? t.substring(0, 400) : t,
          );
        }
      }
    }

    // Descrição … milhar BR com pontos no fim, sem decimais: `recebi pix 1.200` → 1200,00 reais
    m = RegExp(r'^(.+?)\s+(\d{1,3}(?:\.\d{3})+)$', caseSensitive: false).firstMatch(t);
    if (m != null) {
      final brThousands = m.group(2)!;
      final val = _reaisFromBrThousandsDotsOnly(brThousands);
      if (val != null && val > 0) {
        var desc = m.group(1)!.trim();
        if (desc.length >= 2) {
          DateTime? dt;
          final dm = _reData.firstMatch(desc);
          if (dm != null) {
            dt = _parseDataBr(dm.group(1)!);
            desc = desc.replaceFirst(dm.group(0)!, '').trim();
          }
          dt ??= DateTime.now();
          return BankNotificationParseResult(
            valor: val,
            data: dt,
            descricao: desc,
            type: _inferType('$desc $t'),
            suggestedPresetId: _suggestBankPreset(t),
            rawSnippet: t.length > 400 ? t.substring(0, 400) : t,
          );
        }
      }
    }

    // Descrição … valor inteiro no fim: `abastecimento 50` / `recebi pix 1200` (só dígitos = reais inteiros)
    m = RegExp(r'^(.+?)\s+(\d{1,6})$').firstMatch(t);
    if (m != null) {
      final tailDigits = m.group(2)!;
      var n = int.tryParse(tailDigits);
      var desc = m.group(1)!.trim();
      var treatAsCentsFromMerge = false;
      // Evita `farmácia … R$ 8,` + `750` → 750,00: recompõe dígitos quando a descrição termina em `R$ …,`.
      if (n != null && tailDigits.length >= 3) {
        final frac = RegExp(r'R\$\s*(\d+),\s*$', caseSensitive: false).firstMatch(desc);
        if (frac != null) {
          final tailY = int.tryParse(tailDigits);
          final looksLikeYear =
              tailDigits.length == 4 && tailY != null && tailY >= 1900 && tailY <= 2099;
          if (!looksLikeYear) {
            final merged = int.tryParse('${frac.group(1)!}$tailDigits');
            if (merged != null && merged >= 1 && merged < 100000000) {
              n = merged;
              desc = desc.substring(0, frac.start).trim();
              treatAsCentsFromMerge = true;
            }
          }
        }
      }
      if (n != null && n >= 1 && n < 10000000 && desc.length >= 2) {
        if (!(n >= 2000 && n <= 2035 && desc.length < 4)) {
          DateTime? dt;
          final dm = _reData.firstMatch(desc);
          if (dm != null) {
            dt = _parseDataBr(dm.group(1)!);
            desc = desc.replaceFirst(dm.group(0)!, '').trim();
          }
          dt ??= DateTime.now();
          final valor = treatAsCentsFromMerge ? n / 100.0 : n.toDouble();
          return BankNotificationParseResult(
            valor: valor,
            data: dt,
            descricao: desc,
            type: _inferType('$desc $t'),
            suggestedPresetId: _suggestBankPreset(t),
            rawSnippet: t.length > 400 ? t.substring(0, 400) : t,
          );
        }
      }
    }

    return null;
  }

  static BankNotificationParseResult? _tryFreeformLine(String line) => _tryFreeformSegment(line);

  /// Remove sufixos de valor (`r$ 50`) e frases de parcelas do texto livre para categoria / estabelecimento.
  static String? polishSmartPasteDescription(String? desc) {
    if (desc == null) return null;
    var s = desc.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(RegExp(r'\s*r\$\s*[\d.,\s]+$', caseSensitive: false), '').trim();
    s = s.replaceAll(RegExp(r'\s+(?:r\$\s*)?\d{1,6}\s+reais?\s*$', caseSensitive: false), '').trim();
    s = s.replaceFirst(
      RegExp(
        r'^(?:compra|comprei|gasto|gastei|pagamento|paguei|despesa|pix|transferencia|transferência)\s+',
        caseSensitive: false,
      ),
      '',
    ).trim();
    s = _stripParcelaBoilerplatePt(s);
    return s.isEmpty ? desc.trim() : s;
  }

  /// «R$ 8, 750» = 8 + 750 → 87,50 (8750 cênt.); alinha com a fusão em [_tryFreeformSegment] e
  /// evita que [_reValor] apanhe só «8» antes de «, 750».
  static int? _centsFromBrokenRReaisCentsMaisSufix(String t) {
    final m = RegExp(
      r'R\$\s*(\d+)\s*,\s+(\d{3,6})\b',
      caseSensitive: false,
    ).firstMatch(t);
    if (m == null) return null;
    final suf = m.group(2)!;
    if (suf.length == 4) {
      final y = int.tryParse(suf);
      if (y != null && y >= 1900 && y <= 2099) return null;
    }
    return int.tryParse('${m.group(1)}$suf');
  }

  static BankNotificationParseResult parse(String texto) {
    var t = texto.trim();
    if (t.length > kMaxParseInputChars) {
      t = t.substring(0, kMaxParseInputChars);
    }
    final snippet = t.length > 400 ? t.substring(0, 400) : t;

    double? valor;
    final brokenC = _centsFromBrokenRReaisCentsMaisSufix(t);
    if (brokenC != null) {
      valor = brokenC / 100.0;
    } else {
      final vm = _reValor.firstMatch(t);
      if (vm != null && vm.groupCount >= 1) {
        final rawAmt = vm.group(1)!.trim();
        valor = _parseDecimalFlexible(rawAmt)?.abs();
        if (valor != null && valor <= 0) valor = null;
      }
    }

    DateTime? data;
    final dm = _reData.firstMatch(t);
    if (dm != null) {
      data = _parseDataBr(dm.group(1)!);
    }

    String type = _inferType(t);
    var desc = _extractDescricao(t, type) ?? _fallbackDescricao(t);
    desc = polishSmartPasteDescription(desc);
    if (desc != null && desc.trim().isNotEmpty) {
      desc = OcrDescriptionSanity.sanitize(desc);
    }

    return BankNotificationParseResult(
      valor: valor,
      data: data,
      descricao: desc,
      type: type,
      suggestedPresetId: _suggestBankPreset(t),
      rawSnippet: snippet,
    );
  }

  static double? _parseBrDecimal(String s) {
    final normalized = s.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalized);
  }

  /// `1.200` / `12.345.678` só com pontos de milhar (padrão BR), sem parte decimal.
  static double? _reaisFromBrThousandsDotsOnly(String raw) {
    final s = raw.trim();
    if (!RegExp(r'^\d{1,3}(?:\.\d{3})+$').hasMatch(s)) return null;
    final n = int.tryParse(s.replaceAll('.', ''));
    if (n == null || n < 1) return null;
    return n.toDouble();
  }

  static double? _parseDecimalFlexible(String s0) {
    var s = s0.trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(RegExp(r'[^\d,.\-]'), '');
    if (s.isEmpty) return null;

    final lastComma = s.lastIndexOf(',');
    final lastDot = s.lastIndexOf('.');
    if (lastComma >= 0 && lastDot >= 0) {
      if (lastComma > lastDot) {
        return double.tryParse(s.replaceAll('.', '').replaceAll(',', '.'));
      }
      return double.tryParse(s.replaceAll(',', ''));
    }
    if (lastComma >= 0) {
      return double.tryParse(s.replaceAll('.', '').replaceAll(',', '.'));
    }
    // Só ponto e padrão de milhar BR (`1.200`, `12.345.678`) => reais inteiros.
    if (lastDot >= 0 && RegExp(r'^\d{1,3}(?:\.\d{3})+$').hasMatch(s)) {
      return double.tryParse(s.replaceAll('.', ''));
    }
    return double.tryParse(s);
  }

  static DateTime? _parseDateFlexible(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t)) {
      final p = t.split('-');
      final y = int.tryParse(p[0]);
      final m = int.tryParse(p[1]);
      final d = int.tryParse(p[2]);
      if (y == null || m == null || d == null) return null;
      try {
        return DateTime(y, m, d);
      } catch (_) {
        return null;
      }
    }
    if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(t)) {
      return _parseDataBr(t);
    }
    return null;
  }

  static String _csvAt(List<String> row, int idx) =>
      idx >= 0 && idx < row.length ? row[idx] : '';

  static String _detectCsvSeparator(String headerLine) {
    final counts = <String, int>{
      ',': ','.allMatches(headerLine).length,
      ';': ';'.allMatches(headerLine).length,
      '\t': '\t'.allMatches(headerLine).length,
    };
    var best = ',';
    var max = -1;
    for (final e in counts.entries) {
      if (e.value > max) {
        max = e.value;
        best = e.key;
      }
    }
    return best;
  }

  static List<String> _splitCsvLine(String line, String sep) {
    final out = <String>[];
    final sb = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          sb.write('"');
          i++;
          continue;
        }
        inQuotes = !inQuotes;
        continue;
      }
      if (!inQuotes && ch == sep) {
        out.add(sb.toString());
        sb.clear();
        continue;
      }
      sb.write(ch);
    }
    out.add(sb.toString());
    return out;
  }

  static DateTime? _parseDataBr(String s) {
    final parts = s.split('/');
    if (parts.length != 3) return null;
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d == null || m == null || y == null) return null;
    try {
      return DateTime(y, m, d);
    } catch (_) {
      return null;
    }
  }

  static String _inferType(String t) {
    final u = t.toUpperCase();
    int incomeScore = 0;
    int expenseScore = 0;
    for (final r in _incomeHints) {
      if (r.hasMatch(u)) incomeScore++;
    }
    for (final r in _expenseHints) {
      if (r.hasMatch(u)) expenseScore++;
    }
    if (incomeScore > expenseScore) return 'income';
    if (expenseScore > incomeScore) return 'expense';
    // empate: PIX sem "recebido" pode ser envio — assume despesa se houver COMPRA
    if (u.contains('PIX') && !u.contains('RECEB')) return 'expense';
    return 'expense';
  }

  /// Heurística para nome do estabelecimento / descrição curta.
  static String? _extractDescricao(String t, String type) {
    // Bradesco cartões: «… VALOR DE R$ 9,00 SORVETERIA …»
    final valorDe = RegExp(r'VALOR\s+DE\s+R\$\s*[\d.,]+\s+(.+)$', caseSensitive: false).firstMatch(t.replaceAll('\n', ' '));
    if (valorDe != null) {
      final rest = valorDe.group(1)?.trim();
      if (rest != null && rest.length >= 3) return rest;
    }

    final lines = t.split(RegExp(r'[\r\n]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    // Padrão " ... EM NOME_DO_LOCAL" ou "LOCAL: X"
    final em = RegExp(r'\bEM\s+(.{3,80})$', caseSensitive: false).firstMatch(t);
    if (em != null) return em.group(1)?.trim();

    final estab = RegExp(r'(?:ESTABELECIMENTO|LOCAL|COMERCIO)\s*[:\-]\s*(.+)', caseSensitive: false).firstMatch(t);
    if (estab != null) return estab.group(1)?.trim();

    // Linha que não parece só número/data/banco
    for (final line in lines) {
      if (_reValor.hasMatch(line)) continue;
      if (_reData.hasMatch(line) && line.length < 40) continue;
      if (line.toUpperCase().contains('R\$')) continue;
      if (line.length >= 4 && !_looksLikeBankHeader(line)) return line;
    }

    return null;
  }

  static String? _fallbackDescricao(String t) {
    final u = t.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (u.length <= 120) return u.isEmpty ? null : u;
    return u.substring(0, 120);
  }

  static bool _looksLikeBankHeader(String line) {
    final u = line.toUpperCase();
    return u.contains('BANCO') ||
        u.contains('CARTOES') ||
        u.contains('S.A.') ||
        u.contains('PIX') && line.length < 35;
  }

  static String? _suggestBankPreset(String texto) {
    final u = texto.toUpperCase();
    for (final p in kFinanceBankPresets) {
      if (p.id == 'outro_banco' || p.id == 'outro_cartao') continue;
      final name = p.name.toUpperCase();
      if (name.isNotEmpty && u.contains(name)) return p.id;
    }
    // Siglas comuns embutidas no texto
    const pairs = <String, String>{
      'BRADESCO': 'bradesco',
      'ITAU': 'itau',
      'ITAÚ': 'itau',
      'SANTANDER': 'santander',
      'NUBANK': 'nubank',
      'CAIXA': 'caixa',
      'BANCO DO BRASIL': 'bb',
      'BB ': 'bb',
      'INTER': 'inter',
      'SICOOB': 'sicoob',
      'SICREDI': 'sicredi',
      'C6 BANK': 'c6',
      'C6 ': 'c6',
      'PICPAY': 'picpay',
      'MERCADO PAGO': 'mercadopago',
    };
    for (final e in pairs.entries) {
      if (u.contains(e.key)) return e.value;
    }
    return null;
  }
}
