import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../constants/currency_formats.dart';

/// PDF financeiro: cabeçalho moderno + cards de resumo + lista de movimentos (estilo extrato app), sem tabela.
Future<Uint8List> gerarPdfFinanceiroSuperExtrato({
  required List<Map<String, dynamic>> transacoes,
  required String nomeUsuario,
  required String conta,
  required String periodo,
  required double saldoAbertura,
  required double totalReceitas,
  required double totalDespesas,
  Uint8List? logoPngBytes,
  // Líquido do que ficou FORA de receitas/despesas (pagamento de fatura,
  // transferência própria): volta só no saldo final — o saldo não muda.
  double ajusteSaldoForaDosTotais = 0,
}) async {
  final args = <String, dynamic>{
    'ajusteSaldoForaDosTotais': ajusteSaldoForaDosTotais,
    'transacoes': transacoes.map((m) => Map<String, dynamic>.from(m)).toList(),
    'nomeUsuario': nomeUsuario,
    'conta': conta,
    'periodo': periodo,
    'saldoAbertura': saldoAbertura,
    'totalReceitas': totalReceitas,
    'totalDespesas': totalDespesas,
    'logoPngBytes': logoPngBytes,
  };
  // Android/iOS: monta o PDF fora da thread da tela (ano inteiro com milhares
  // de lançamentos travava a UI). Web não tem isolate: gera na thread (o
  // relatório já cede a vez antes). Se o isolate falhar, gera aqui mesmo.
  if (!kIsWeb) {
    try {
      return await Isolate.run(() => _financeSuperExtratoComputeAsync(args));
    } catch (_) {}
  }
  return _financeSuperExtratoComputeAsync(args);
}

String _clamp(String s, [int max = 120]) {
  final t = s.replaceAll('\n', ' ').trim();
  if (t.length <= max) return t;
  return '${t.substring(0, max - 1)}...';
}

const _mesesAbrev = <String>[
  'JAN',
  'FEV',
  'MAR',
  'ABR',
  'MAI',
  'JUN',
  'JUL',
  'AGO',
  'SET',
  'OUT',
  'NOV',
  'DEZ',
];

String _labelDiaPt(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')} ${_mesesAbrev[d.month - 1]} ${d.year}';

/// Extrai título (linha principal) e categoria do mapa ou da string legada «Categoria: … — Descricao: …».
(String titulo, String categoria) _tituloECategoria(Map<String, dynamic> t) {
  final tituloOpt = (t['titulo'] ?? t['tituloLinha'] ?? '').toString().trim();
  final catOpt = (t['categoria'] ?? t['category'] ?? '').toString().trim();
  if (tituloOpt.isNotEmpty || catOpt.isNotEmpty) {
    final tit = tituloOpt.isNotEmpty
        ? tituloOpt
        : (catOpt.isNotEmpty ? catOpt : _clamp((t['descricao'] ?? '').toString(), 80));
    return (tit, catOpt);
  }
  final desc = (t['descricao'] ?? '').toString().trim();
  if (desc.contains('Categoria:')) {
    var rest = desc.split(RegExp(r'Categoria:\s*', caseSensitive: false)).last.trim();
    if (rest.contains('—')) {
      final parts = rest.split('—');
      final catPart = parts.first.trim();
      var tail = parts.sublist(1).join('—').trim();
      for (final prefix in ['Descricao:', 'Descrição:', 'Descricao :', 'Descrição :']) {
        if (tail.toLowerCase().startsWith(prefix.toLowerCase())) {
          tail = tail.substring(prefix.length).trim();
          break;
        }
      }
      return (tail.isNotEmpty ? _clamp(tail, 100) : _clamp(catPart, 100), _clamp(catPart, 60));
    }
    for (final sep in ['Descricao:', 'Descrição:']) {
      final idx = rest.toLowerCase().indexOf(sep.toLowerCase());
      if (idx >= 0) {
        final cat = rest.substring(0, idx).trim();
        final tit = rest.substring(idx + sep.length).trim();
        return (_clamp(tit.isNotEmpty ? tit : cat, 100), _clamp(cat, 60));
      }
    }
    return (_clamp(rest, 100), '');
  }
  return (_clamp(desc.isNotEmpty ? desc : 'Movimento', 100), '');
}

DateTime? _dayFromRow(Map<String, dynamic> t) {
  final ms = (t['sortMs'] as num?)?.toInt();
  if (ms != null && ms != 0) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return DateTime(d.year, d.month, d.day);
  }
  final ds = (t['data'] ?? '').toString().trim();
  if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(ds)) {
    try {
      final p = DateFormat('dd/MM/yyyy').parse(ds);
      return DateTime(p.year, p.month, p.day);
    } catch (_) {}
  }
  return null;
}

Future<Uint8List> _financeSuperExtratoComputeAsync(Map<String, dynamic> p) async {
  final rawList = (p['transacoes'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  final nomeUsuario = (p['nomeUsuario'] ?? '').toString().trim();
  final conta = (p['conta'] ?? '').toString().trim();
  final periodo = (p['periodo'] ?? '').toString().trim();
  final saldoAbertura = (p['saldoAbertura'] as num?)?.toDouble() ?? 0.0;
  final totalReceitas = (p['totalReceitas'] as num?)?.toDouble() ?? 0.0;
  final totalDespesas = (p['totalDespesas'] as num?)?.toDouble() ?? 0.0;
  final logoBytes = p['logoPngBytes'] as Uint8List?;

  rawList.sort((a, b) {
    final ma = (a['sortMs'] as num?)?.toInt() ?? 0;
    final mb = (b['sortMs'] as num?)?.toInt() ?? 0;
    if (ma != 0 || mb != 0) return ma.compareTo(mb);
    final sa = (a['data'] ?? '').toString();
    final sb = (b['data'] ?? '').toString();
    return sa.compareTo(sb);
  });

  final ajusteFora = (p['ajusteSaldoForaDosTotais'] as num?)?.toDouble() ?? 0.0;
  final saldoPeriodo = totalReceitas - totalDespesas + ajusteFora;
  final saldoFinal = saldoAbertura + saldoPeriodo;
  final now = DateTime.now();
  final emitido =
      '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

  final primary = PdfColor.fromInt(0xFF122B6B);
  final onPrimary = PdfColors.white;
  final muted = PdfColors.grey700;
  final green = PdfColor.fromInt(0xFF166534);
  final red = PdfColor.fromInt(0xFF991B1B);
  final blueSaldo = PdfColor.fromInt(0xFF1D4ED8);

  /// Insight: categoria de despesa com maior valor no conjunto exportado.
  String? insightTopDespesa;
  double maxDespCat = 0;
  final porCat = <String, double>{};
  for (final t in rawList) {
    final tipo = (t['tipo'] ?? '').toString().toLowerCase();
    if (tipo != 'despesa') continue;
    final valorRaw = t['valor'];
    final valor = valorRaw is num ? valorRaw.toDouble().abs() : double.tryParse(valorRaw.toString())?.abs() ?? 0.0;
    final (_, cat) = _tituloECategoria(t);
    final key = cat.trim().isEmpty ? 'Sem categoria' : cat.trim();
    porCat[key] = (porCat[key] ?? 0) + valor;
  }
  for (final e in porCat.entries) {
    if (e.value > maxDespCat) {
      maxDespCat = e.value;
      insightTopDespesa = e.key;
    }
  }

  pw.Widget footer(pw.Context ctx) {
    return pw.Container(
      alignment: pw.Alignment.center,
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            'Gerado por WISDOMAPP',
            style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold, color: muted),
          ),
          pw.SizedBox(height: 2),
          pw.Text(
            'Emitido em $emitido  |  Pag. ${ctx.pageNumber} de ${ctx.pagesCount}',
            style: pw.TextStyle(fontSize: 8, color: muted),
          ),
        ],
      ),
    );
  }

  pw.Widget headerBand() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 16, horizontal: 18),
      decoration: pw.BoxDecoration(
        gradient: pw.LinearGradient(
          colors: [PdfColor.fromInt(0xFF0B1F4B), PdfColor.fromInt(0xFF2D5BFF), PdfColor.fromInt(0xFF12B5A5)],
        ),
        borderRadius: pw.BorderRadius.circular(14),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          if (logoBytes != null && logoBytes.isNotEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(right: 12),
              child: pw.Image(pw.MemoryImage(logoBytes), width: 44, height: 44, fit: pw.BoxFit.contain),
            ),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'WISDOMAPP',
                  style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: onPrimary),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Extrato Financeiro',
                  style: pw.TextStyle(fontSize: 11, color: onPrimary),
                ),
              ],
            ),
          ),
          pw.Container(
            constraints: const pw.BoxConstraints(maxWidth: 190),
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: pw.BoxDecoration(
              color: const PdfColor(1, 1, 1, 0.2),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Text(
              periodo.isEmpty ? 'Período' : _clamp('Período: $periodo', 90),
              maxLines: 4,
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: onPrimary),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget resumoTresCards() {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: _cardResumo(
            label: 'Receitas',
            valor: CurrencyFormats.formatBRL(totalReceitas),
            cor: green,
            fundo: PdfColor.fromInt(0xFFDCFCE7),
            destaque: false,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          child: _cardResumo(
            label: 'Despesas',
            valor: CurrencyFormats.formatBRL(totalDespesas),
            cor: red,
            fundo: PdfColor.fromInt(0xFFFEE2E2),
            destaque: false,
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Expanded(
          flex: 2,
          child: _cardResumo(
            label: 'Saldo final',
            valor: CurrencyFormats.formatBRL(saldoFinal),
            cor: saldoFinal >= 0 ? blueSaldo : red,
            fundo: saldoFinal >= 0 ? PdfColor.fromInt(0xFFDBEAFE) : PdfColor.fromInt(0xFFFEE2E2),
            destaque: true,
          ),
        ),
      ],
    );
  }

  /// Para onde foi o dinheiro, com barra proporcional.
  ///
  /// O insight de uma linha só dizia a MAIOR categoria. Quem imprime o extrato
  /// quer ver a divisão inteira — e a barra responde «quanto» sem precisar
  /// comparar números de cabeça.
  pw.Widget? blocoCategorias() {
    if (porCat.isEmpty || maxDespCat <= 0) return null;
    final ordenadas = porCat.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = ordenadas.fold<double>(0, (acc, e) => acc + e.value);
    if (total <= 0) return null;
    final top = ordenadas.take(8).toList();
    final resto = ordenadas.skip(8).fold<double>(0, (acc, e) => acc + e.value);

    pw.Widget linha(String nome, double valor) {
      final fracao = (valor / total).clamp(0.0, 1.0);
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 6),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(children: [
              pw.Expanded(
                child: pw.Text(_clamp(nome, 46),
                    style: pw.TextStyle(fontSize: 9, color: PdfColor.fromInt(0xFF0F172A))),
              ),
              pw.Text(
                '${CurrencyFormats.formatBRL(valor)}  ${(fracao * 100).round()}%',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: muted),
              ),
            ]),
            pw.SizedBox(height: 2),
            // O pacote de PDF não tem FractionallySizedBox: a proporção sai de
            // dois Expanded com `flex` inteiro (milésimos da largura).
            pw.Row(children: [
              pw.Expanded(
                flex: ((fracao <= 0.02 ? 0.02 : fracao) * 1000).round(),
                child: pw.Container(
                  height: 5,
                  decoration: pw.BoxDecoration(
                    color: red,
                    borderRadius: pw.BorderRadius.circular(999),
                  ),
                ),
              ),
              pw.Expanded(
                flex: (1000 - ((fracao <= 0.02 ? 0.02 : fracao) * 1000).round())
                    .clamp(1, 1000),
                child: pw.Container(
                  height: 5,
                  decoration: pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFE2E8F0),
                    borderRadius: pw.BorderRadius.circular(999),
                  ),
                ),
              ),
            ]),
          ],
        ),
      );
    }

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFFAFAFA),
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('Para onde foi o dinheiro',
              style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: primary)),
          pw.SizedBox(height: 8),
          for (final e in top) linha(e.key, e.value),
          if (resto > 0) linha('Outras categorias', resto),
        ],
      ),
    );
  }

  pw.Widget? insightLinha() {
    if (insightTopDespesa == null || maxDespCat <= 0) return null;
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFF0FDF4),
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: PdfColor.fromInt(0xFFBBF7D0), width: 0.8),
      ),
      child: pw.Row(
          children: [
          pw.Expanded(
            child: pw.Text(
              'Você gastou mais com «${_clamp(insightTopDespesa, 48)}» neste período.',
              style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF14532D)),
            ),
          ),
        ],
      ),
    );
  }

  /// Um movimento = um bloco (evita «meio item» entre páginas na maioria dos casos).
  pw.Widget blocoMovimento({
    required String titulo,
    required String categoria,
    String observacao = '',
    required bool isReceita,
    required double valorAbs,
  }) {
    final cor = isReceita ? green : red;
    // ASCII '-' (não U+2212 «menos matemático»): fontes Latin do PDF podem não ter o glifo e mostrar «tofu».
    final sinal = isReceita ? '+' : '-';
    final valorTxt = CurrencyFormats.formatBRL(valorAbs);
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 10),
      padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
        boxShadow: [
          pw.BoxShadow(color: PdfColors.grey300, blurRadius: 2, offset: const PdfPoint(0, 1)),
        ],
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _clamp(titulo, 90),
                  style: pw.TextStyle(fontSize: 11.5, fontWeight: pw.FontWeight.bold, color: PdfColor.fromInt(0xFF0F172A)),
                ),
                if (categoria.isNotEmpty) ...[
                  pw.SizedBox(height: 3),
                  pw.Text(
                    _clamp(categoria, 70),
                    style: pw.TextStyle(fontSize: 9, color: muted),
                  ),
                ],
                // A observação é o «por quê» do lançamento. Num extrato que
                // vai para o contador ou para uma prestação de contas, é
                // justamente ela que evita a pergunta de volta.
                if (observacao.isNotEmpty) ...[
                  pw.SizedBox(height: 4),
                  pw.Text(
                    _clamp(observacao, 160),
                    style: pw.TextStyle(
                      fontSize: 8.5,
                      color: muted,
                      fontStyle: pw.FontStyle.italic,
                    ),
                  ),
                ],
              ],
            ),
          ),
          pw.SizedBox(width: 10),
          pw.Text(
            '$sinal $valorTxt',
            style: pw.TextStyle(
              fontSize: 12.5,
              fontWeight: pw.FontWeight.bold,
              color: cor,
            ),
          ),
        ],
      ),
    );
  }

  final movimentoWidgets = <pw.Widget>[];

  if (saldoAbertura.abs() > 0.0001) {
    movimentoWidgets.add(
      pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.all(12),
        decoration: pw.BoxDecoration(
          color: PdfColor.fromInt(0xFFF8FAFC),
          borderRadius: pw.BorderRadius.circular(12),
          border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'Saldo inicial',
                  style: pw.TextStyle(fontSize: 9, color: muted, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Referência antes dos movimentos do período',
                  style: pw.TextStyle(fontSize: 8, color: muted),
                ),
              ],
            ),
            pw.Text(
              CurrencyFormats.formatBRL(saldoAbertura),
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: blueSaldo),
            ),
          ],
        ),
      ),
    );
  }

  DateTime? diaAnterior;
  for (final t in rawList) {
    final tipo = (t['tipo'] ?? '').toString().toLowerCase();
    final valorRaw = t['valor'];
    final valorAbs = valorRaw is num ? valorRaw.toDouble().abs() : double.tryParse(valorRaw.toString())?.abs() ?? 0.0;
    final isReceita = tipo == 'receita';
    final day = _dayFromRow(t);

    if (day != null && (diaAnterior == null || day != diaAnterior)) {
      diaAnterior = day;
      movimentoWidgets.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(top: 6, bottom: 8),
          child: pw.Row(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromInt(0xFFEEF2FF),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Text(
                  _labelDiaPt(day),
                  style: pw.TextStyle(
                    fontSize: 10,
                    fontWeight: pw.FontWeight.bold,
                    color: primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final parsed = _tituloECategoria(t);
    var titulo = parsed.$1;
    var categoria = parsed.$2;
    if (titulo.isEmpty) titulo = isReceita ? 'Receita' : 'Despesa';
    if (categoria.isNotEmpty && categoria == titulo) categoria = '';

    movimentoWidgets.add(
      blocoMovimento(
        titulo: titulo,
        categoria: categoria,
        observacao: (t['observacao'] ?? '').toString().trim(),
        isReceita: isReceita,
        valorAbs: valorAbs,
      ),
    );
  }

  final pdf = pw.Document(
    compress: true,
    theme: pw.ThemeData(),
    title: 'Extrato Financeiro',
    author: 'WISDOMAPP',
    creator: 'WISDOMAPP',
    subject: periodo.isEmpty ? 'Financeiro' : periodo,
  );

  final insight = insightLinha();
  final categorias = blocoCategorias();
  final porMes = _blocoTotaisPorMes(rawList, primary: primary, green: green, red: red, muted: muted);

  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(22),
      // Padrão do pacote = 20 páginas: o extrato do ano inteiro (centenas de
      // movimentos) falhava com «Não foi possível gerar o PDF».
      maxPages: 1000,
      footer: footer,
      build: (pw.Context context) => [
        headerBand(),
        pw.SizedBox(height: 12),
        pw.Text(
          'Utilizador: ${nomeUsuario.isEmpty ? '-' : _clamp(nomeUsuario, 80)}',
          style: pw.TextStyle(fontSize: 9.5, color: muted),
        ),
        pw.Text(
          'Conta: ${conta.isEmpty ? 'Todas as contas' : _clamp(conta, 80)}',
          style: pw.TextStyle(fontSize: 9.5, color: muted),
        ),
        pw.SizedBox(height: 14),
        resumoTresCards(),
        if (insight != null) ...[
          pw.SizedBox(height: 12),
          insight,
        ],
        if (categorias != null) ...[
          pw.SizedBox(height: 12),
          categorias,
        ],
        if (porMes != null) ...[
          pw.SizedBox(height: 12),
          porMes,
        ],
        pw.SizedBox(height: 14),
        pw.Text(
          'Movimentações',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: primary),
        ),
        pw.SizedBox(height: 8),
        if (movimentoWidgets.isEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.all(16),
            child: pw.Text(
              'Nenhum movimento neste período.',
              style: pw.TextStyle(fontSize: 10, color: muted),
            ),
          )
        else
          ...movimentoWidgets,
      ],
    ),
  );

  return Uint8List.fromList(await pdf.save());
}

/// Totais por mês (receitas, despesas, saldo) em tabela com zebra — só quando
/// o período tem 2 meses ou mais (relatório anual, trimestral…).
pw.Widget? _blocoTotaisPorMes(
  List<Map<String, dynamic>> rows, {
  required PdfColor primary,
  required PdfColor green,
  required PdfColor red,
  required PdfColor muted,
}) {
  final rec = <int, double>{};
  final des = <int, double>{};
  for (final t in rows) {
    final d = _dayFromRow(t);
    if (d == null) continue;
    final k = d.year * 100 + d.month;
    final v = t['valor'];
    final valor = v is num ? v.toDouble().abs() : double.tryParse('$v')?.abs() ?? 0.0;
    if ((t['tipo'] ?? '').toString().toLowerCase() == 'receita') {
      rec[k] = (rec[k] ?? 0) + valor;
    } else {
      des[k] = (des[k] ?? 0) + valor;
    }
  }
  final meses = {...rec.keys, ...des.keys}.toList()..sort();
  if (meses.length < 2) return null;

  pw.Widget cel(String s, {PdfColor? cor, bool bold = false, pw.Alignment a = pw.Alignment.centerRight}) =>
      pw.Container(
        alignment: a,
        padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: pw.Text(s,
            style: pw.TextStyle(
                fontSize: 9, color: cor, fontWeight: bold ? pw.FontWeight.bold : null)),
      );

  var tr = 0.0, td = 0.0;
  final linhas = <pw.TableRow>[
    pw.TableRow(
      decoration: pw.BoxDecoration(color: primary),
      children: [
        cel('Mês', cor: PdfColors.white, bold: true, a: pw.Alignment.centerLeft),
        cel('Receitas', cor: PdfColors.white, bold: true),
        cel('Despesas', cor: PdfColors.white, bold: true),
        cel('Saldo', cor: PdfColors.white, bold: true),
      ],
    ),
  ];
  for (var i = 0; i < meses.length; i++) {
    final k = meses[i];
    final r = rec[k] ?? 0, d = des[k] ?? 0;
    tr += r;
    td += d;
    linhas.add(pw.TableRow(
      decoration: pw.BoxDecoration(
          color: i.isOdd ? PdfColor.fromInt(0xFFF8FAFC) : PdfColors.white),
      children: [
        cel('${_mesesAbrev[k % 100 - 1]}/${k ~/ 100}', a: pw.Alignment.centerLeft),
        cel(CurrencyFormats.formatBRL(r), cor: green),
        cel(CurrencyFormats.formatBRL(d), cor: red),
        cel(CurrencyFormats.formatBRL(r - d), cor: r - d >= 0 ? green : red, bold: true),
      ],
    ));
  }
  linhas.add(pw.TableRow(
    decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEF2FF)),
    children: [
      cel('Total', bold: true, a: pw.Alignment.centerLeft),
      cel(CurrencyFormats.formatBRL(tr), cor: green, bold: true),
      cel(CurrencyFormats.formatBRL(td), cor: red, bold: true),
      cel(CurrencyFormats.formatBRL(tr - td), cor: tr - td >= 0 ? green : red, bold: true),
    ],
  ));
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('Totais por mês',
          style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: primary)),
      pw.SizedBox(height: 6),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.6),
        columnWidths: const {
          0: pw.FlexColumnWidth(1.1),
          1: pw.FlexColumnWidth(1.3),
          2: pw.FlexColumnWidth(1.3),
          3: pw.FlexColumnWidth(1.3),
        },
        children: linhas,
      ),
    ],
  );
}

pw.Widget _cardResumo({
  required String label,
  required String valor,
  required PdfColor cor,
  required PdfColor fundo,
  required bool destaque,
}) {
  return pw.Container(
    padding: pw.EdgeInsets.symmetric(
      vertical: destaque ? 14 : 10,
      horizontal: 10,
    ),
    decoration: pw.BoxDecoration(
      color: fundo,
      borderRadius: pw.BorderRadius.circular(12),
      border: pw.Border.all(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.6),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label.toUpperCase(),
          style: pw.TextStyle(
            fontSize: destaque ? 8.5 : 7.5,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.grey700,
            letterSpacing: 0.3,
          ),
        ),
        pw.SizedBox(height: destaque ? 8 : 6),
        pw.Text(
          valor,
          maxLines: 2,
          style: pw.TextStyle(
            fontSize: destaque ? 13 : 10.5,
            fontWeight: pw.FontWeight.bold,
            color: cor,
          ),
        ),
      ],
    ),
  );
}
