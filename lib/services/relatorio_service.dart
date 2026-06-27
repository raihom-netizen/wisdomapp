import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as img;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../constants/currency_formats.dart';
import '../constants/date_time_formats.dart';
import '../utils/agenda_finance_pending_utils.dart';
import '../utils/produtividade_ocorrencias_pdf_partition.dart';
import 'pdf_launcher.dart';

/// Argumentos só com dados serializáveis para [Isolate.run] (PDF financeiro mensal).
class RelatorioMensalIsolateArgs {
  RelatorioMensalIsolateArgs({
    required this.mes,
    required this.receitas,
    required this.despesas,
    required this.totalReceitas,
    required this.totalDespesas,
    required this.saldoAbertura,
    required this.includeCategoryBreakdownPage,
    required this.receitasPorCategoria,
    required this.despesasPorCategoria,
    required this.pdfTableOnlyLayout,
    /// PNG já otimizado (carregado na isolate principal — [Isolate.run] não tem [rootBundle]).
    this.logoPngBytes,
  });

  final String mes;
  final List<Map<String, dynamic>> receitas;
  final List<Map<String, dynamic>> despesas;
  final double totalReceitas;
  final double totalDespesas;
  final double saldoAbertura;
  final bool includeCategoryBreakdownPage;
  final Map<String, double>? receitasPorCategoria;
  final Map<String, double>? despesasPorCategoria;
  final bool pdfTableOnlyLayout;
  final Uint8List? logoPngBytes;
}

/// Cores Clean Premium no PDF (azul escuro, teal, cinzas).
final PdfColor _pdfPrimary = PdfColors.blue900;
final PdfColor _pdfAccent = PdfColor.fromInt(0xFF12B5A5);
final PdfColor _pdfGrey700 = PdfColors.grey700;
final PdfColor _pdfGrey300 = PdfColors.grey300;
final PdfColor _pdfGrey100 = PdfColors.grey100;
/// Verde escuro para receitas (balanceta).
final PdfColor _pdfVerdeEscuro = PdfColor.fromInt(0xFF1B5E20);
/// Despesas no PDF (vermelho profissional, bom contraste em barras).
final PdfColor _pdfDespesaBar = PdfColor.fromInt(0xFFC62828);

class _BalancetaRow {
  final String data;
  final DateTime sortDate;
  final String descricao;
  final String conta;
  final bool isReceita;
  final num valor;
  _BalancetaRow({
    required this.data,
    required this.sortDate,
    required this.descricao,
    this.conta = '',
    required this.isReceita,
    required this.valor,
  });
}

class _AccCatBh {
  int qJa = 0;
  int qPend = 0;
  double hJa = 0;
  double hPend = 0;
  double vJa = 0;
  double vPend = 0;
}

/// Uma linha do resumo por categoria (Estado, Município, Particular, sem financeiro, compromissos).
class ResumoBancoHorasCategoriaPdf {
  const ResumoBancoHorasCategoriaPdf({
    required this.titulo,
    required this.qtdJaTirado,
    required this.qtdATirar,
    required this.horasJaTirado,
    required this.horasATirar,
    required this.valorJaRecebido,
    required this.valorATirar,
    required this.mostrarColunaValor,
  });

  final String titulo;
  final int qtdJaTirado;
  final int qtdATirar;
  final double horasJaTirado;
  final double horasATirar;
  final double valorJaRecebido;
  final double valorATirar;
  /// false para compromissos e plantões sem financeiro (PDF mostra "-" nas colunas de valor).
  final bool mostrarColunaValor;
}

/// Resumo do banco de horas no topo do PDF (horas diurnas/noturnas, valores, totais).
class ResumoBancoHorasPdf {
  const ResumoBancoHorasPdf({
    required this.horasDiurnasTotal,
    required this.horasNoturnasTotal,
    required this.horasDiurnasRealizadas,
    required this.horasNoturnasRealizadas,
    required this.horasDiurnasPendentes,
    required this.horasNoturnasPendentes,
    required this.valorJaRecebido,
    required this.valorAReceber,
    this.categorias,
    this.horasPlantaoMarcadoPago = 0,
    this.quantidadeCompromissos = 0,
    this.horasCompromissos = 0,
    this.horasProfissionalSemFinanceiroPainel = 0,
  });

  final double horasDiurnasTotal;
  final double horasNoturnasTotal;
  final double horasDiurnasRealizadas;
  final double horasNoturnasRealizadas;
  final double horasDiurnasPendentes;
  final double horasNoturnasPendentes;
  final double valorJaRecebido;
  final double valorAReceber;
  final List<ResumoBancoHorasCategoriaPdf>? categorias;
  /// Horas em plantões profissionais marcados como «pago» (inclui hora extra já paga).
  final double horasPlantaoMarcadoPago;
  final int quantidadeCompromissos;
  final double horasCompromissos;
  /// Plantões profissionais sem financeiro ativado no painel (vínculo/valor/local).
  final double horasProfissionalSemFinanceiroPainel;

  double get valorTotal => valorJaRecebido + valorAReceber;
}

/// Geração de relatórios PDF no estilo Clean Premium: cabeçalho com marca,
/// resumo financeiro **em dados e tabelas** (sem gráficos — gráficos só na tela do app)
/// e balanceta de lançamentos. Usado pelo plano Premium.
/// Conteúdo incluído no PDF exportado da Agenda.
enum AgendaPdfContentFilter { financeiro, particular, todos }

class RelatorioService {
  /// Margens iguais em **todos** os PDFs A4 deste serviço (~24 pt cada lado).
  static const pw.EdgeInsets _kA4PageMargin = pw.EdgeInsets.all(24);

  /// Nome do arquivo conforme tipo, período e opcionalmente filtro (ex.: produtividade: todos, sem folga, usadas folga).
  /// [tipo] um de: 'despesa_receita' | 'banco_horas' | 'produtividade_ocorrencias'
  /// [filtroSufixo] opcional; para produtividade use ex.: null (todos), 'sem folga', 'usadas folga'
  static String reportFilenameFromPeriod(String tipo, DateTime dateStart, DateTime dateEnd, [String? filtroSufixo]) {
    final d1 = '${dateStart.day.toString().padLeft(2, '0')}-${dateStart.month.toString().padLeft(2, '0')}-${dateStart.year}';
    final d2 = '${dateEnd.day.toString().padLeft(2, '0')}-${dateEnd.month.toString().padLeft(2, '0')}-${dateEnd.year}';
    final faixa = '$d1 a $d2';
    final suf = (filtroSufixo != null && filtroSufixo.trim().isNotEmpty) ? ' ${filtroSufixo.trim()}' : '';
    switch (tipo) {
      case 'despesa_receita':
        return 'controle despesa receita $faixa$suf';
      case 'banco_horas':
        return 'banco de horas $faixa';
      case 'produtividade_ocorrencias':
        return 'produtividade_ocorrências $faixa$suf';
      case 'compromissos_audiencia':
        return 'compromissos audiencia $faixa';
      default:
        return 'relatorio $faixa$suf';
    }
  }

  /// Normaliza texto para exibição em relatórios (PDF/tela): preserva acentos e
  /// caracteres especiais digitados pelo usuário; remove apenas caracteres invisíveis/controle.
  static String sanitizeForReport(String s) {
    if (s.isEmpty) return s;
    return s
        .replaceAll('\u00A0', ' ')  // non-breaking space
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')  // zero-width chars
        .replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]'), '')  // control chars
        .trim();
  }

  /// Evita texto longo demais em células de tabela (layout PDF estável).
  static String pdfClampUiLine(String s, [int maxChars = 56]) {
    final t = sanitizeForReport(s).trim();
    if (t.length <= maxChars) return t;
    if (maxChars < 4) return t.substring(0, maxChars.clamp(1, t.length));
    return '${t.substring(0, maxChars - 1)}…';
  }

  /// Fontes com suporte UTF-8 (pt-BR). Só memoriza **sucesso** — falha não fica cacheada (senão Web/Android ficavam presos em Helvetica).
  static pw.ThemeData? _latinPdfThemeReady;
  static Future<pw.ThemeData>? _latinPdfThemeInFlight;

  static Future<pw.ThemeData> _latinPdfTheme() async {
    final ok = _latinPdfThemeReady;
    if (ok != null) return ok;

    final inflight = _latinPdfThemeInFlight;
    if (inflight != null) return inflight;

    final fut = _latinPdfThemeLoadOnce();
    _latinPdfThemeInFlight = fut;
    return fut;
  }

  /// Pré-carrega fontes Latin (Noto) para o PDF. Na Web evita a 1.ª geração «parada» muitos segundos.
  static Future<void> warmUpPdfLatinFonts() async {
    try {
      await _latinPdfTheme();
    } catch (_) {}
  }

  static Uint8List? _cachedPdfLogoBytes;
  static bool _pdfLogoLoadFailed = false;

  /// Redimensiona PNG do ícone (~largura alvo pt no PDF ~72dpi lógico) para PDF menor e mais rápido.
  static Uint8List? _resizeLogoForPdfEmbed(Uint8List raw, {int maxSide = 160}) {
    try {
      final decoded = img.decodeImage(raw);
      if (decoded == null) return raw;
      final w = decoded.width;
      final h = decoded.height;
      final m = w > h ? w : h;
      if (m <= maxSide) return raw;
      final nw = (w * maxSide / m).round();
      final nh = (h * maxSide / m).round();
      final scaled = img.copyResize(decoded, width: nw, height: nh, interpolation: img.Interpolation.linear);
      return Uint8List.fromList(img.encodePng(scaled));
    } catch (_) {
      return raw;
    }
  }

  /// Ícone da app para cabeçalhos PDF — uma leitura + cache (não falha o relatório se o asset sumir).
  static Future<Uint8List?> loadPdfLogoBytesOnce() async {
    if (_pdfLogoLoadFailed) return null;
    final hit = _cachedPdfLogoBytes;
    if (hit != null) return hit;
    try {
      final data = await rootBundle.load('assets/images/icon.png');
      final raw = data.buffer.asUint8List();
      final opt = _resizeLogoForPdfEmbed(raw) ?? raw;
      _cachedPdfLogoBytes = opt;
      return opt;
    } catch (_) {
      _pdfLogoLoadFailed = true;
      return null;
    }
  }

  /// Fontes + logo (chamar cedo: Relatórios, export Financeiro).
  static Future<void> warmUpPdfAssets() async {
    await Future.wait<Object?>([
      warmUpPdfLatinFonts(),
      loadPdfLogoBytesOnce(),
    ]);
  }

  /// Partilha nativa (WhatsApp, Drive, etc.) — mesmo contrato da [ReportPreviewScreen].
  static Future<void> sharePdfBytes(Uint8List bytes, String filename) async {
    var name = filename.trim();
    if (!name.toLowerCase().endsWith('.pdf')) name = '$name.pdf';
    name = name.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    await Share.shareXFiles(
      [XFile.fromData(bytes, name: name, mimeType: 'application/pdf')],
      text: 'Relatório WISDOMAPP',
    );
  }

  static Future<pw.ThemeData> _latinPdfThemeLoadOnce() async {
    try {
      // Preferência: `google_fonts/NotoSans-*.ttf` no bundle (printing resolve offline — fiável em Web/Android).
      // Sem assets, PdfGoogleFonts baixa em runtime e pode falhar → Helvetica → erro ao gravar pt-BR.
      final t = await _downloadNotoLatinPdfTheme().timeout(
        const Duration(seconds: 45),
        onTimeout: () => throw TimeoutException('noto_sans'),
      );
      _latinPdfThemeReady = t;
      return t;
    } catch (_) {
      /// Sem rede ou timeout: tema padrão (não guardamos — próxima exportação tenta de novo).
      return pw.ThemeData();
    } finally {
      _latinPdfThemeInFlight = null;
    }
  }

  static Future<pw.ThemeData> _downloadNotoLatinPdfTheme() async {
    final base = await PdfGoogleFonts.notoSansRegular();
    final bold = await PdfGoogleFonts.notoSansBold();
    final italic = await PdfGoogleFonts.notoSansItalic();
    final boldItalic = await PdfGoogleFonts.notoSansBoldItalic();
    return pw.ThemeData.withFont(
      base: base,
      bold: bold,
      italic: italic,
      boldItalic: boldItalic,
    );
  }

  static const Duration _kPdfSaveTimeout = Duration(minutes: 3);

  /// Evita `pdf.save()` pendurado (PDFs grandes / Web / CPU).
  static Future<Uint8List> _pdfDocumentToBytes(pw.Document pdf) async {
    final raw = await pdf.save().timeout(
      _kPdfSaveTimeout,
      onTimeout: () => throw TimeoutException('pdf.save'),
    );
    return Uint8List.fromList(raw);
  }

  /// Worker para [Isolate.run]: monta o PDF financeiro mensal fora da isolate da UI (VM).
  static Future<Uint8List> _mensalFinanceiroPdfIsolateWork(RelatorioMensalIsolateArgs a) async {
    final pdf = await _buildMensalPdf(
      mes: a.mes,
      receitas: a.receitas,
      despesas: a.despesas,
      totalReceitas: a.totalReceitas,
      totalDespesas: a.totalDespesas,
      saldoAbertura: a.saldoAbertura,
      includeCategoryBreakdownPage: a.includeCategoryBreakdownPage,
      receitasPorCategoria: a.receitasPorCategoria,
      despesasPorCategoria: a.despesasPorCategoria,
      pdfTableOnlyLayout: a.pdfTableOnlyLayout,
      logoPngBytes: a.logoPngBytes,
    );
    return await _pdfDocumentToBytes(pdf);
  }

  static String _formatarPeriodoFaixa(String mes) {
    final m = mes.trim();
    final aPos = m.toLowerCase().indexOf(' a ');
    if (aPos > 0) {
      final parte1 = m.substring(0, aPos).replaceFirst(RegExp(r'^[Dd]e\s+'), '').trim();
      final parte2 = m.substring(aPos + 3).trim();
      if (parte1.isNotEmpty && parte2.isNotEmpty) {
        return 'DATA INICIAL: $parte1 A DATA FINAL: $parte2';
      }
    }
    return 'Período: $mes';
  }
  /// Gera o PDF do relatório em formato balanceta e retorna (bytes, nome do arquivo).
  /// **Não inclui gráficos** (pizza, barras, linhas): apenas cards, indicadores e tabelas.
  /// [saldoAbertura] opcional: saldo anterior ao início do período (igual ao painel); se informado, o PDF mostra Saldo de abertura e Saldo (acum.).
  /// [pdfTableOnlyLayout] true = layout mínimo (cabeçalho + período + balanceta, sem cards e sem bloco de resumo por categorias).
  static Future<(Uint8List, String)> buildRelatorioMensalBytes({
    required String mes,
    required List<Map<String, dynamic>> receitas,
    required List<Map<String, dynamic>> despesas,
    required double totalReceitas,
    required double totalDespesas,
    double saldoAbertura = 0,
    String? suggestedFilename,
    bool includeCategoryBreakdownPage = false,
    Map<String, double>? receitasPorCategoria,
    Map<String, double>? despesasPorCategoria,
    bool pdfTableOnlyLayout = false,
  }) async {
    final logoBytes = await loadPdfLogoBytesOnce();
    if (!kIsWeb) {
      try {
        final args = RelatorioMensalIsolateArgs(
          mes: mes,
          receitas: receitas.map((m) => Map<String, dynamic>.from(m)).toList(),
          despesas: despesas.map((m) => Map<String, dynamic>.from(m)).toList(),
          totalReceitas: totalReceitas,
          totalDespesas: totalDespesas,
          saldoAbertura: saldoAbertura,
          includeCategoryBreakdownPage: includeCategoryBreakdownPage,
          receitasPorCategoria: receitasPorCategoria == null
              ? null
              : Map<String, double>.from(receitasPorCategoria),
          despesasPorCategoria: despesasPorCategoria == null
              ? null
              : Map<String, double>.from(despesasPorCategoria),
          pdfTableOnlyLayout: pdfTableOnlyLayout,
          logoPngBytes: logoBytes,
        );
        final raw = await Isolate.run(() => _mensalFinanceiroPdfIsolateWork(args));
        return (raw, suggestedFilename ?? _nomeFinanceiro);
      } catch (e, st) {
        debugPrint('buildRelatorioMensalBytes: isolate falhou, gera na main isolate. $e\n$st');
      }
    }
    final pdf = await _buildMensalPdf(
      mes: mes,
      receitas: receitas,
      despesas: despesas,
      totalReceitas: totalReceitas,
      totalDespesas: totalDespesas,
      saldoAbertura: saldoAbertura,
      includeCategoryBreakdownPage: includeCategoryBreakdownPage,
      receitasPorCategoria: receitasPorCategoria,
      despesasPorCategoria: despesasPorCategoria,
      pdfTableOnlyLayout: pdfTableOnlyLayout,
      logoPngBytes: logoBytes,
    );
    final raw = await _pdfDocumentToBytes(pdf);
    return (raw, suggestedFilename ?? _nomeFinanceiro);
  }

  /// Gera o PDF do relatório em formato balanceta: colunas separadas RECEITAS | DESPESAS.
  /// **Sem gráficos** (gráficos só na tela do app); PDF com cards, resumo em tabelas e detalhamento.
  static Future<void> gerarRelatorioMensal({
    required String mes,
    required List<Map<String, dynamic>> receitas,
    required List<Map<String, dynamic>> despesas,
    required double totalReceitas,
    required double totalDespesas,
    String? suggestedFilename,
  }) async {
    final (bytes, name) = await buildRelatorioMensalBytes(
      mes: mes,
      receitas: receitas,
      despesas: despesas,
      totalReceitas: totalReceitas,
      totalDespesas: totalDespesas,
      suggestedFilename: suggestedFilename,
      includeCategoryBreakdownPage: false,
      pdfTableOnlyLayout: false,
    );
    try {
      await Printing.layoutPdf(name: name, onLayout: (PdfPageFormat format) async => bytes);
    } catch (e) {
      if (e.toString().contains('MissingPluginException') ||
          e.toString().contains('printPdf') ||
          e.toString().contains('No implementation') ||
          e.toString().contains('layoutPdf')) {
        openPdfFallback(bytes, filename: name);
      } else {
        rethrow;
      }
    }
  }

  static pw.Widget _buildPdfCategoriaTabelaResumo(String titulo, Map<String, double> valores, {required bool isReceita}) {
    final entries = valores.entries.where((e) => e.value.abs() > 0.0001).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return pw.SizedBox();
    final corValor = isReceita ? _pdfVerdeEscuro : PdfColors.red800;
    final zebra = PdfColor.fromInt(0xFFF5F7FA);
    final rows = <pw.TableRow>[
      pw.TableRow(
        decoration: pw.BoxDecoration(color: _pdfGrey100),
        children: [
          _pdfCellHeader('Categoria'),
          _pdfCellHeader('Total', alignRight: true),
        ],
      ),
    ];
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final label = pdfClampUiLine(e.key.isEmpty ? 'Sem categoria' : e.key, 52);
      final txt = isReceita
          ? '+ ${CurrencyFormats.formatBRL(e.value)}'
          : CurrencyFormats.formatBRL(-e.value.abs());
      rows.add(
        pw.TableRow(
          decoration: pw.BoxDecoration(color: i.isOdd ? zebra : PdfColors.white),
          children: [
            _pdfCellBody(label),
            _pdfCellBody(txt, alignRight: true, color: corValor, bold: true),
          ],
        ),
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          titulo,
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, color: _pdfPrimary),
        ),
        pw.SizedBox(height: 8),
        _wrapRoundedPdfSurface(
          pw.Table(
            border: pw.TableBorder(
              horizontalInside: pw.BorderSide(color: _pdfGrey300, width: 0.5),
              verticalInside: pw.BorderSide(color: _pdfGrey300, width: 0.5),
            ),
            columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1.4)},
            children: rows,
          ),
        ),
      ],
    );
  }

  static pw.Widget _pdfCellHeader(String t, {bool alignRight = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: pw.Align(
        alignment: alignRight ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(
          t,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: _pdfGrey700),
        ),
      ),
    );
  }

  static pw.Widget _pdfCellBody(
    String t, {
    bool alignRight = false,
    PdfColor? color,
    bool bold = false,
    int maxLines = 12,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: pw.Align(
        alignment: alignRight ? pw.Alignment.centerRight : pw.Alignment.centerLeft,
        child: pw.Text(
          t,
          maxLines: maxLines,
          overflow: pw.TextOverflow.clip,
          softWrap: true,
          style: pw.TextStyle(
            fontSize: 9,
            color: color ?? PdfColors.black,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// Rodapé por página no [pw.MultiPage]: numeração + data (usa [Context.pagesCount] só em header/footer).
  static pw.Widget Function(pw.Context) _pdfFooterFinanceiroEmitido(String dataGeracao) {
    return (pw.Context ctx) {
      return pw.Container(
        alignment: pw.Alignment.centerRight,
        padding: const pw.EdgeInsets.only(top: 8),
        child: pw.Text(
          'Pag. ${ctx.pageNumber} de ${ctx.pagesCount}  |  Emitido em $dataGeracao  |  WISDOMAPP',
          style: pw.TextStyle(fontSize: 8.5, color: _pdfGrey700),
        ),
      );
    };
  }

  static pw.Widget _wrapRoundedPdfSurface(pw.Widget innerTable) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.ClipRRect(
        horizontalRadius: 10,
        verticalRadius: 10,
        child: pw.Container(
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _pdfGrey300, width: 0.65),
            color: PdfColors.white,
          ),
          child: innerTable,
        ),
      ),
    );
  }

  static Future<pw.Document> _buildMensalPdf({
    required String mes,
    required List<Map<String, dynamic>> receitas,
    required List<Map<String, dynamic>> despesas,
    required double totalReceitas,
    required double totalDespesas,
    double saldoAbertura = 0,
    bool includeCategoryBreakdownPage = false,
    Map<String, double>? receitasPorCategoria,
    Map<String, double>? despesasPorCategoria,
    bool pdfTableOnlyLayout = false,
    Uint8List? logoPngBytes,
  }) async {
    final theme = await _latinPdfTheme();
    final pdf = pw.Document(
      compress: true,
      theme: theme,
      title: 'Relatório Despesas e Receitas',
      author: 'WISDOMAPP',
      creator: 'WISDOMAPP',
      subject: mes,
    );
    final now = DateTime.now();
    final dataGeracao =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final saldoPeriodo = totalReceitas - totalDespesas;
    final saldoAcumulado = saldoAbertura + saldoPeriodo;

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _kA4PageMargin,
        footer: _pdfFooterFinanceiroEmitido(dataGeracao),
        build: (pw.Context context) {
          return [
            // --- HEADER MODERNO (faixa gradiente simulada) ---
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: pw.BoxDecoration(
                color: _pdfPrimary,
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logoPngBytes != null && logoPngBytes.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 14),
                      child: pw.Image(
                        pw.MemoryImage(logoPngBytes),
                        width: 44,
                        height: 44,
                        fit: pw.BoxFit.contain,
                      ),
                    ),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'WISDOMAPP',
                          style: pw.TextStyle(
                            fontSize: pdfTableOnlyLayout ? 18 : 22,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          pdfTableOnlyLayout ? 'Relatório (balanceta compacta)' : 'Despesas e Receitas',
                          style: pw.TextStyle(
                            fontSize: 11,
                            color: const PdfColor(1, 1, 1, 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Container(
                    constraints: const pw.BoxConstraints(maxWidth: 220),
                    padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor(1, 1, 1, 0.24),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Text(
                      'Período: ${pdfClampUiLine(mes, 85)}',
                      maxLines: 4,
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 11,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: pdfTableOnlyLayout ? 14 : 24),

            if (!pdfTableOnlyLayout) ...[
              // --- RESUMO EM CARDS (saldo de abertura igual ao painel); largura dos cards cabe em A4 (4 × ~128pt) ---
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildPdfStatCard(
                    'Saldo de abertura',
                    CurrencyFormats.formatBRL(saldoAbertura),
                    saldoAbertura >= 0 ? _pdfAccent : PdfColors.red700,
                  ),
                  _buildPdfStatCard(
                    'Receitas',
                    '+ ${CurrencyFormats.formatBRL(totalReceitas)}',
                    _pdfVerdeEscuro,
                  ),
                  _buildPdfStatCard(
                    'Despesas',
                    CurrencyFormats.formatBRL(-totalDespesas),
                    PdfColors.red800,
                  ),
                  _buildPdfStatCard(
                    'Saldo (acum.)',
                    CurrencyFormats.formatBRL(saldoAcumulado),
                    saldoAcumulado >= 0 ? _pdfAccent : PdfColors.red700,
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              _buildPdfFinanceDataPanel(
                totalReceitas: totalReceitas,
                totalDespesas: totalDespesas,
                saldoPeriodo: saldoPeriodo,
                saldoAcumulado: saldoAcumulado,
                receitasPorCategoria: receitasPorCategoria,
                despesasPorCategoria: despesasPorCategoria,
              ),
              pw.SizedBox(height: 12),
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                child: pw.Text(
                  _formatarPeriodoFaixa(mes),
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
              ),
              pw.SizedBox(height: 12),
            ] else ...[
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                decoration: pw.BoxDecoration(
                  color: _pdfGrey100,
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: _pdfGrey300),
                ),
                child: pw.Text(
                  _formatarPeriodoFaixa(mes),
                  style: pw.TextStyle(
                    fontSize: 11,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.black,
                  ),
                ),
              ),
              pw.SizedBox(height: 12),
            ],

            // --- Detalhamento: colunas RECEITAS | DESPESAS ---
            pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                'Detalhamento',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: _pdfPrimary,
                ),
              ),
            ),
            _buildBalancetaTable(receitas, despesas, totalReceitas: totalReceitas, totalDespesas: totalDespesas),
          ];
        },
      ),
    );

    if (includeCategoryBreakdownPage &&
        receitasPorCategoria != null &&
        despesasPorCategoria != null) {
      final anyR = receitasPorCategoria.values.any((v) => v.abs() > 0.0001);
      final anyD = despesasPorCategoria.values.any((v) => v.abs() > 0.0001);
      if (anyR || anyD) {
        pdf.addPage(
          pw.MultiPage(
            pageFormat: PdfPageFormat.a4,
            margin: _kA4PageMargin,
            footer: _pdfFooterFinanceiroEmitido(dataGeracao),
            build: (pw.Context context) {
              return [
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: pw.BoxDecoration(
                    color: _pdfPrimary,
                    borderRadius: pw.BorderRadius.circular(10),
                  ),
                  child: pw.Text(
                    'Resumo por categoria',
                    style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                ),
                pw.SizedBox(height: 16),
                if (anyR) _buildPdfCategoriaTabelaResumo('Receitas por categoria', receitasPorCategoria, isReceita: true),
                if (anyR && anyD) pw.SizedBox(height: 20),
                if (anyD) _buildPdfCategoriaTabelaResumo('Despesas por categoria', despesasPorCategoria, isReceita: false),
              ];
            },
          ),
        );
      }
    }
    return pdf;
  }

  static const _nomeFinanceiro = 'RELATORIO FINANCEIRO WISDOMAPP';
  static const _nomeBancoHoras = 'RELATORIO AGENDA WISDOMAPP';

  /// Evita uma única [pw.Table] gigante (OOM em relatório anual). Cada bloco = cabeçalho + até N linhas.
  static const int _balancetaRowsPerChunk = 32;

  static pw.TableRow _balancetaHeaderRow() {
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: _pdfPrimary),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: pw.Text('Data', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: pw.Text('Conta', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: pw.Text('Descrição', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: pw.Text('RECEITAS', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: pw.Text('DESPESAS', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
        ),
      ],
    );
  }

  static pw.Widget _buildBalancetaTable(
    List<Map<String, dynamic>> receitas,
    List<Map<String, dynamic>> despesas, {
    double totalReceitas = 0,
    double totalDespesas = 0,
  }) {
    DateTime parseBalancetaDate(dynamic v) {
      if (v == null) return DateTime(2000, 1, 1);
      if (v is DateTime) return v;
      if (v is String && v.isNotEmpty) {
        final parts = v.split('/');
        if (parts.length == 3) {
          final d = int.tryParse(parts[0]) ?? 1;
          final m = int.tryParse(parts[1]) ?? 1;
          final y = int.tryParse(parts[2]) ?? 2000;
          return DateTime(y, m, d);
        }
      }
      return DateTime(2000, 1, 1);
    }
    final r = receitas.map((e) {
      final dataStr = sanitizeForReport((e['data'] ?? '').toString());
      final contaRaw = (e['conta'] ?? '').toString().trim();
      return _BalancetaRow(
        data: dataStr,
        sortDate: e['sortDate'] as DateTime? ?? parseBalancetaDate(e['data']),
        descricao: sanitizeForReport((e['descricao'] ?? '').toString()),
        conta: contaRaw.isEmpty ? '—' : sanitizeForReport(contaRaw),
        isReceita: true,
        valor: (e['valor'] ?? 0) as num,
      );
    }).toList();
    final d = despesas.map((e) {
      final dataStr = sanitizeForReport((e['data'] ?? '').toString());
      final contaRaw = (e['conta'] ?? '').toString().trim();
      return _BalancetaRow(
        data: dataStr,
        sortDate: e['sortDate'] as DateTime? ?? parseBalancetaDate(e['data']),
        descricao: sanitizeForReport((e['descricao'] ?? '').toString()),
        conta: contaRaw.isEmpty ? '—' : sanitizeForReport(contaRaw),
        isReceita: false,
        valor: (e['valor'] ?? 0) as num,
      );
    }).toList();
    final merged = <_BalancetaRow>[...r, ...d];
    merged.sort((a, b) => a.sortDate.compareTo(b.sortDate));
    final zebraTint = PdfColor.fromInt(0xFFF5F7FA);
    final dataRows = <pw.TableRow>[];
    for (var i = 0; i < merged.length; i++) {
      final row = merged[i];
      dataRows.add(pw.TableRow(
        decoration: pw.BoxDecoration(
          color: i.isOdd ? zebraTint : PdfColors.white,
          border: pw.Border(
            bottom: pw.BorderSide(color: _pdfGrey300, width: 0.5),
          ),
        ),
        children: [
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: pw.Text(row.data, style: pw.TextStyle(fontSize: 9, color: _pdfGrey700)),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            child: pw.Text(
              row.conta,
              style: pw.TextStyle(fontSize: 8, color: _pdfGrey700),
              maxLines: 2,
              overflow: pw.TextOverflow.clip,
              softWrap: true,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: pw.Text(
              row.descricao,
              style: pw.TextStyle(fontSize: 9, color: PdfColors.black),
              maxLines: 4,
              overflow: pw.TextOverflow.clip,
              softWrap: true,
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                row.isReceita ? '+ ${CurrencyFormats.formatBRL(row.valor)}' : '',
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _pdfVerdeEscuro),
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                row.isReceita ? '' : CurrencyFormats.formatBRL(-row.valor),
                style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.red800),
              ),
            ),
          ),
        ],
      ));
    }
    final totalRow = pw.TableRow(
      decoration: pw.BoxDecoration(color: _pdfGrey100, border: pw.Border(top: pw.BorderSide(color: _pdfGrey300, width: 2))),
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: pw.Text('TOTAL', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _pdfPrimary)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 10),
          child: pw.Text('', style: pw.TextStyle(fontSize: 9)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: pw.Text('', style: pw.TextStyle(fontSize: 10)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              '+ ${CurrencyFormats.formatBRL(totalReceitas)}',
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: _pdfVerdeEscuro),
            ),
          ),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              CurrencyFormats.formatBRL(-totalDespesas),
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.red800),
            ),
          ),
        ),
      ],
    );
    const columnWidths = {
      0: pw.FlexColumnWidth(1.0),
      1: pw.FlexColumnWidth(1.05),
      2: pw.FlexColumnWidth(2.55),
      3: pw.FlexColumnWidth(1.28),
      4: pw.FlexColumnWidth(1.28),
    };
    final balancetaInner = pw.TableBorder(
      horizontalInside: pw.BorderSide(color: _pdfGrey300, width: 0.5),
      verticalInside: pw.BorderSide(color: _pdfGrey300, width: 0.5),
    );
    if (dataRows.length <= _balancetaRowsPerChunk) {
      return _wrapRoundedPdfSurface(
        pw.Table(
          border: balancetaInner,
          columnWidths: columnWidths,
          children: [
            _balancetaHeaderRow(),
            ...dataRows,
            totalRow,
          ],
        ),
      );
    }
    final chunks = <pw.Widget>[];
    for (var s = 0; s < dataRows.length; s += _balancetaRowsPerChunk) {
      final e = math.min(s + _balancetaRowsPerChunk, dataRows.length);
      final slice = dataRows.sublist(s, e);
      final isLast = e >= dataRows.length;
      chunks.add(
        _wrapRoundedPdfSurface(
          pw.Table(
            border: balancetaInner,
            columnWidths: columnWidths,
            children: [
              _balancetaHeaderRow(),
              ...slice,
              if (isLast) totalRow,
            ],
          ),
        ),
      );
    }
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < chunks.length; i++) ...[
          if (i > 0) pw.SizedBox(height: 14),
          chunks[i],
        ],
      ],
    );
  }

  /// Card de resumo no PDF (Despesas e Receitas). Largura 128pt para 4 cards caberem em A4 (margem 28×2). Valor em fonte menor para não quebrar.
  static pw.Widget _buildPdfStatCard(String label, String value, PdfColor color) {
    return pw.Container(
      width: 128,
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _pdfGrey300, width: 1),
        borderRadius: pw.BorderRadius.circular(10),
        color: _pdfGrey100,
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(
            label.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
              color: _pdfGrey700,
              letterSpacing: 0.5,
            ),
            maxLines: 1,
            overflow: pw.TextOverflow.clip,
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            value,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: color,
            ),
            maxLines: 2,
            overflow: pw.TextOverflow.clip,
          ),
        ],
      ),
    );
  }

  static List<MapEntry<String, double>> _topMapEntries(Map<String, double> m, int n) {
    final list = m.entries.where((e) => e.value.abs() > 0.0001).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list.take(n).toList();
  }

  /// Tabela compacta de categorias (sem gráficos). Usada no resumo em dados do PDF financeiro.
  static pw.Widget _buildPdfCategoriaMiniTable(
    String titulo,
    List<MapEntry<String, double>> entries, {
    required bool isReceita,
  }) {
    if (entries.isEmpty) {
      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            titulo,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _pdfPrimary),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            'Sem lançamentos neste grupo.',
            style: pw.TextStyle(fontSize: 8.5, color: _pdfGrey700),
          ),
        ],
      );
    }
    final corValor = isReceita ? _pdfVerdeEscuro : _pdfDespesaBar;
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          titulo,
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: _pdfPrimary),
        ),
        pw.SizedBox(height: 6),
        pw.Table(
          border: pw.TableBorder.all(color: _pdfGrey300, width: 0.5),
          columnWidths: const {0: pw.FlexColumnWidth(2.6), 1: pw.FlexColumnWidth(1.4)},
          children: [
            pw.TableRow(
              decoration: pw.BoxDecoration(color: _pdfGrey100),
              children: [
                _pdfCellHeader('Categoria'),
                _pdfCellHeader('Total', alignRight: true),
              ],
            ),
            ...entries.map((e) {
              final label = pdfClampUiLine(e.key.isEmpty ? 'Sem categoria' : e.key, 52);
              final txt = isReceita
                  ? '+ ${CurrencyFormats.formatBRL(e.value)}'
                  : CurrencyFormats.formatBRL(-e.value.abs());
              return pw.TableRow(
                children: [
                  _pdfCellBody(label),
                  _pdfCellBody(txt, alignRight: true, color: corValor, bold: true),
                ],
              );
            }),
          ],
        ),
      ],
    );
  }

  /// Resumo financeiro no PDF **só com dados** (indicadores + tabelas). Gráficos permanecem no app.
  static pw.Widget _buildPdfFinanceDataPanel({
    required double totalReceitas,
    required double totalDespesas,
    required double saldoPeriodo,
    required double saldoAcumulado,
    Map<String, double>? receitasPorCategoria,
    Map<String, double>? despesasPorCategoria,
  }) {
    final hasMovement = totalReceitas > 0.0001 || totalDespesas > 0.0001;
    if (!hasMovement) {
      return pw.SizedBox.shrink();
    }

    final pctDespSobreRec =
        totalReceitas > 0.0001 ? (totalDespesas / totalReceitas * 100).clamp(0.0, 9999.0) : null;

    final topR = _topMapEntries(receitasPorCategoria ?? const {}, 8);
    final topD = _topMapEntries(despesasPorCategoria ?? const {}, 8);

    pw.Widget indicador(String rotulo, String valor, PdfColor cor) {
      return pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: pw.BoxDecoration(
            color: PdfColors.white,
            borderRadius: pw.BorderRadius.circular(10),
            border: pw.Border.all(color: PdfColor(0.90, 0.92, 0.95)),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                rotulo,
                style: pw.TextStyle(fontSize: 7.8, fontWeight: pw.FontWeight.bold, color: _pdfGrey700),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                valor,
                style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold, color: cor),
              ),
            ],
          ),
        ),
      );
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        borderRadius: pw.BorderRadius.circular(16),
        border: pw.Border.all(color: PdfColor(0.86, 0.89, 0.93)),
        gradient: pw.LinearGradient(
          begin: pw.Alignment.topLeft,
          end: pw.Alignment.bottomRight,
          colors: [
            PdfColor(0.93, 0.95, 0.99),
            PdfColor(0.99, 0.995, 1.0),
          ],
        ),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Container(
                width: 4,
                height: 22,
                decoration: pw.BoxDecoration(
                  color: _pdfAccent,
                  borderRadius: pw.BorderRadius.circular(2),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Resumo em dados (período)',
                      style: pw.TextStyle(
                        fontSize: 13,
                        fontWeight: pw.FontWeight.bold,
                        color: _pdfPrimary,
                      ),
                    ),
                    pw.Text(
                      'Gráficos apenas na tela do aplicativo. No PDF: totais, indicadores e tabelas.',
                      style: pw.TextStyle(fontSize: 8.5, color: _pdfGrey700, height: 1.28),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 12),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              indicador(
                'Saldo do período (receitas - despesas)',
                CurrencyFormats.formatBRL(saldoPeriodo),
                saldoPeriodo >= 0 ? _pdfAccent : PdfColors.red700,
              ),
              pw.SizedBox(width: 8),
              indicador(
                'Saldo acumulado (com abertura)',
                CurrencyFormats.formatBRL(saldoAcumulado),
                saldoAcumulado >= 0 ? _pdfAccent : PdfColors.red700,
              ),
              if (pctDespSobreRec != null) ...[
                pw.SizedBox(width: 8),
                indicador(
                  'Despesas / receitas',
                  '${pctDespSobreRec.toStringAsFixed(1)} %',
                  PdfColors.blueGrey800,
                ),
              ],
            ],
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _buildPdfCategoriaMiniTable(
                  'Receitas por categoria (principais)',
                  topR,
                  isReceita: true,
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _buildPdfCategoriaMiniTable(
                  'Despesas por categoria (principais)',
                  topD,
                  isReceita: false,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Formata horas: total no período + detalhe diurno/noturno (ASCII, seguro em PDF).
  static String formatHorasLinhaPdf(double hoursDay, double hoursNight) {
    if (hoursDay <= 0 && hoursNight <= 0) return '-';
    String f(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
    final tot = f(hoursDay + hoursNight);
    return '$tot h tot. · ${f(hoursDay)} d | ${f(hoursNight)} n';
  }

  /// Versão compacta para células da tabela (evita quebra vertical no PDF).
  static String formatHorasLinhaPdfCompact(double hoursDay, double hoursNight) {
    if (hoursDay <= 0 && hoursNight <= 0) return '—';
    String f(double v) => v.toStringAsFixed(1).replaceAll('.', ',');
    return '${f(hoursDay + hoursNight)} h\n${f(hoursDay)} d | ${f(hoursNight)} n';
  }

  static String _fmtH(double v) => v.toStringAsFixed(1).replaceAll('.', ',');

  /// Agrega linhas para o quadro "Por categoria" do PDF.
  /// Cada mapa: [isCompromisso], [temFinanceiro] (como [ScaleEntry.temFinanceiroHabilitadoNoPainel]),
  /// [employerType] ('state'|'municipality'|'private'|outro), [jaTirado], [hoursDay], [hoursNight],
  /// [valor] (parcela no período), [paid].
  static List<ResumoBancoHorasCategoriaPdf> buildCategoriasResumoBancoHoras(
    List<Map<String, dynamic>> linhas,
  ) {
    final keys = <String>['state', 'municipality', 'private', 'sem_fin', 'compromisso'];
    const titulos = <String, String>{
      'state': 'Estado (financeiro)',
      'municipality': 'Município (financeiro)',
      'private': 'Particular (financeiro)',
      'sem_fin': 'Plantões sem financeiro no painel',
      'compromisso': 'Compromissos',
    };
    final accs = <String, _AccCatBh>{for (final k in keys) k: _AccCatBh()};

    for (final L in linhas) {
      final isComp = L['isCompromisso'] == true;
      final temFin = L['temFinanceiro'] == true;
      final etRaw = (L['employerType'] ?? 'private').toString();
      final ja = L['jaTirado'] == true;
      final hd = ((L['hoursDay'] ?? 0) as num).toDouble();
      final hn = ((L['hoursNight'] ?? 0) as num).toDouble();
      final valor = ((L['valor'] ?? 0) as num).toDouble();
      final paid = L['paid'] == true;

      late final String bucket;
      if (isComp) {
        bucket = 'compromisso';
      } else if (!temFin) {
        bucket = 'sem_fin';
      } else if (etRaw == 'state') {
        bucket = 'state';
      } else if (etRaw == 'municipality') {
        bucket = 'municipality';
      } else {
        bucket = 'private';
      }

      final acc = accs[bucket]!;
      final h = hd + hn;
      if (ja) {
        acc.qJa++;
        acc.hJa += h;
      } else {
        acc.qPend++;
        acc.hPend += h;
      }
      final mostrarValor = bucket != 'compromisso' && bucket != 'sem_fin';
      if (mostrarValor) {
        if (paid) {
          acc.vJa += valor;
        } else {
          acc.vPend += valor;
        }
      }
    }

    final out = <ResumoBancoHorasCategoriaPdf>[];
    for (final key in keys) {
      final a = accs[key]!;
      if (a.qJa + a.qPend == 0) continue;
      out.add(ResumoBancoHorasCategoriaPdf(
        titulo: titulos[key]!,
        qtdJaTirado: a.qJa,
        qtdATirar: a.qPend,
        horasJaTirado: a.hJa,
        horasATirar: a.hPend,
        valorJaRecebido: a.vJa,
        valorATirar: a.vPend,
        mostrarColunaValor: key != 'compromisso' && key != 'sem_fin',
      ));
    }
    return out;
  }

  static pw.Widget _buildTabelaCategoriasBancoHoras(List<ResumoBancoHorasCategoriaPdf> cats) {
    if (cats.isEmpty) return pw.SizedBox();
    pw.Widget cell(String t,
            {bool bold = false, pw.TextAlign align = pw.TextAlign.left, double fs = 7}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: pw.Text(
            t,
            textAlign: align,
            style: pw.TextStyle(
              fontSize: fs,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
              color: bold ? PdfColors.blue900 : PdfColors.black,
            ),
          ),
        );

    String vFmt(ResumoBancoHorasCategoriaPdf c, double v) =>
        c.mostrarColunaValor ? CurrencyFormats.formatBRL(v) : '-';

    pw.Widget headCell(String t, {pw.TextAlign align = pw.TextAlign.left}) => pw.Container(
          color: PdfColors.blue900,
          padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          child: pw.Text(
            t,
            textAlign: align,
            style: pw.TextStyle(
              fontSize: 7,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
            ),
          ),
        );

    final rows = <pw.TableRow>[
      pw.TableRow(
        children: [
          headCell('Categoria'),
          headCell('Nº já', align: pw.TextAlign.right),
          headCell('Nº a tirar', align: pw.TextAlign.right),
          headCell('H já', align: pw.TextAlign.right),
          headCell('H a tirar', align: pw.TextAlign.right),
          headCell('R\$ já', align: pw.TextAlign.right),
          headCell('R\$ a receber', align: pw.TextAlign.right),
          headCell('Tot. Nº', align: pw.TextAlign.right),
          headCell('Tot. h', align: pw.TextAlign.right),
        ],
      ),
    ];
    var sumQJa = 0, sumQP = 0;
    var sumHJa = 0.0, sumHP = 0.0, sumVJa = 0.0, sumVP = 0.0;
    for (final c in cats) {
      sumQJa += c.qtdJaTirado;
      sumQP += c.qtdATirar;
      sumHJa += c.horasJaTirado;
      sumHP += c.horasATirar;
      if (c.mostrarColunaValor) {
        sumVJa += c.valorJaRecebido;
        sumVP += c.valorATirar;
      }
      final qTot = c.qtdJaTirado + c.qtdATirar;
      final hTot = c.horasJaTirado + c.horasATirar;
      rows.add(pw.TableRow(
        children: [
          cell(c.titulo, fs: 7),
          cell('${c.qtdJaTirado}', align: pw.TextAlign.right),
          cell('${c.qtdATirar}', align: pw.TextAlign.right),
          cell('${_fmtH(c.horasJaTirado)}', align: pw.TextAlign.right),
          cell('${_fmtH(c.horasATirar)}', align: pw.TextAlign.right),
          cell(vFmt(c, c.valorJaRecebido), align: pw.TextAlign.right),
          cell(vFmt(c, c.valorATirar), align: pw.TextAlign.right),
          cell('$qTot', align: pw.TextAlign.right),
          cell(_fmtH(hTot), align: pw.TextAlign.right),
        ],
      ));
    }
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromInt(0xFFE8EAF6)),
      children: [
        cell('TOTAL (todas as linhas)', bold: true, fs: 7),
        cell('$sumQJa', bold: true, align: pw.TextAlign.right),
        cell('$sumQP', bold: true, align: pw.TextAlign.right),
        cell(_fmtH(sumHJa), bold: true, align: pw.TextAlign.right),
        cell(_fmtH(sumHP), bold: true, align: pw.TextAlign.right),
        cell(CurrencyFormats.formatBRL(sumVJa), bold: true, align: pw.TextAlign.right),
        cell(CurrencyFormats.formatBRL(sumVP), bold: true, align: pw.TextAlign.right),
        cell('${sumQJa + sumQP}', bold: true, align: pw.TextAlign.right),
        cell(_fmtH(sumHJa + sumHP), bold: true, align: pw.TextAlign.right),
      ],
    ));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 6),
          child: pw.Text(
            'Resumo por categoria (escalas / compromissos e vínculos)',
            style: pw.TextStyle(
              fontSize: 9,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.blue900,
            ),
          ),
        ),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(2.4),
            1: const pw.FlexColumnWidth(0.55),
            2: const pw.FlexColumnWidth(0.65),
            3: const pw.FlexColumnWidth(0.55),
            4: const pw.FlexColumnWidth(0.65),
            5: const pw.FlexColumnWidth(0.95),
            6: const pw.FlexColumnWidth(0.95),
            7: const pw.FlexColumnWidth(0.55),
            8: const pw.FlexColumnWidth(0.55),
          },
          children: rows,
        ),
      ],
    );
  }

  static pw.Widget _buildResumoBancoHorasModerno(ResumoBancoHorasPdf r) {
    pw.TableRow row(String k, String v, {bool bold = false}) => pw.TableRow(
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: pw.Text(
                k,
                style: pw.TextStyle(
                  fontSize: bold ? 10 : 9,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: bold ? PdfColors.blue900 : PdfColors.grey800,
                ),
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              child: pw.Text(
                v,
                textAlign: pw.TextAlign.right,
                style: pw.TextStyle(
                  fontSize: bold ? 11 : 9,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: bold ? PdfColors.blue900 : PdfColors.black,
                ),
              ),
            ),
          ],
        );

    return pw.Container(
      decoration: pw.BoxDecoration(
        color: PdfColor.fromInt(0xFFE8EAF6),
        borderRadius: pw.BorderRadius.circular(12),
        border: pw.Border.all(color: PdfColor.fromInt(0xFF3949AB), width: 1.2),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const pw.BoxDecoration(
              color: PdfColors.blue900,
              borderRadius: pw.BorderRadius.vertical(top: pw.Radius.circular(11)),
            ),
            child: pw.Text(
              'RESUMO DO BANCO DE HORAS (PERÍODO)',
              style: pw.TextStyle(
                color: PdfColors.white,
                fontSize: 11,
                fontWeight: pw.FontWeight.bold,
                letterSpacing: 0.4,
              ),
            ),
          ),
          pw.Table(
            border: pw.TableBorder.symmetric(
              inside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
            ),
            columnWidths: {0: const pw.FlexColumnWidth(2.2), 1: const pw.FlexColumnWidth(1.3)},
            children: [
              row('Horas diurnas (total no período)', '${_fmtH(r.horasDiurnasTotal)} h'),
              row('Horas noturnas (total no período)', '${_fmtH(r.horasNoturnasTotal)} h'),
              row('Horas diurnas já cumpridas / realizadas', '${_fmtH(r.horasDiurnasRealizadas)} h'),
              row('Horas noturnas já cumpridas / realizadas', '${_fmtH(r.horasNoturnasRealizadas)} h'),
              row('Horas diurnas a cumprir (pendentes)', '${_fmtH(r.horasDiurnasPendentes)} h'),
              row('Horas noturnas a cumprir (pendentes)', '${_fmtH(r.horasNoturnasPendentes)} h'),
              row('Valores já recebidos (plantão pago)', CurrencyFormats.formatBRL(r.valorJaRecebido)),
              row('Valores a receber (pendente)', CurrencyFormats.formatBRL(r.valorAReceber)),
              row('TOTAL VALORES NO PERÍODO', CurrencyFormats.formatBRL(r.valorTotal), bold: true),
              row(
                'Horas em plantões marcados como «pago» (incl. hora extra)',
                '${_fmtH(r.horasPlantaoMarcadoPago)} h',
              ),
              row('Compromissos no período (quantidade)', '${r.quantidadeCompromissos}'),
              row('Horas em compromissos', '${_fmtH(r.horasCompromissos)} h'),
              row(
                'Horas em plantões sem financeiro no painel',
                '${_fmtH(r.horasProfissionalSemFinanceiroPainel)} h',
              ),
            ],
          ),
          if (r.categorias != null && r.categorias!.isNotEmpty) ...[
            pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(10, 12, 10, 10),
              child: _buildTabelaCategoriasBancoHoras(r.categorias!),
            ),
          ],
        ],
      ),
    );
  }

  /// Gera bytes do PDF de escalas e retorna (bytes, nome do arquivo). Para preview primeiro.
  static Future<(Uint8List, String)> buildRelatorioEscalasBytes({
    required String periodo,
    required List<Map<String, dynamic>> escalas,
    required double totalRecebido,
    required double totalPendente,
    String? notaProximoMes,
    String? reportTitle,
    String? suggestedFilename,
    ResumoBancoHorasPdf? resumoBancoHoras,
  }) async {
    final pdf = await _buildEscalasPdf(
      periodo: periodo,
      escalas: escalas,
      totalRecebido: totalRecebido,
      totalPendente: totalPendente,
      notaProximoMes: notaProximoMes,
      reportTitle: reportTitle,
      resumoBancoHoras: resumoBancoHoras,
    );
    final bytes = await _pdfDocumentToBytes(pdf);
    return (bytes, suggestedFilename ?? _nomeBancoHoras);
  }

  /// Gera PDF do resumo de escalas (Clean Premium): lista de plantões, valores e status.
  /// [periodo] ex: "Janeiro/2025" ou "01/01/2025 a 31/01/2025"
  /// [notaProximoMes] opcional: observação padrão GO (23h59 / 00h01-07h próximo mês)
  /// [reportTitle] opcional: ex. "Relatório Banco de Horas" quando chamado do módulo Relatórios
  static Future<void> gerarRelatorioEscalas({
    required String periodo,
    required List<Map<String, dynamic>> escalas,
    required double totalRecebido,
    required double totalPendente,
    String? notaProximoMes,
    String? reportTitle,
    String? suggestedFilename,
  }) async {
    final (bytes, name) = await buildRelatorioEscalasBytes(
      periodo: periodo,
      escalas: escalas,
      totalRecebido: totalRecebido,
      totalPendente: totalPendente,
      notaProximoMes: notaProximoMes,
      reportTitle: reportTitle,
      suggestedFilename: suggestedFilename,
      resumoBancoHoras: null,
    );
    try {
      await Printing.layoutPdf(name: name, onLayout: (PdfPageFormat format) async => bytes);
    } catch (e) {
      if (e.toString().contains('MissingPluginException') ||
          e.toString().contains('printPdf') ||
          e.toString().contains('No implementation')) {
        openPdfFallback(bytes, filename: name);
      } else {
        rethrow;
      }
    }
  }

  /// Evita uma única tabela gigante no PDF de escalas (reduz picos de memória/travamento).
  static const int _escalasRowsPerChunk = 180;

  static const Map<int, pw.TableColumnWidth> _escalasPdfColumnWidths = {
    0: pw.FlexColumnWidth(0.95),
    1: pw.FlexColumnWidth(1.1),
    2: pw.FlexColumnWidth(2.85),
    3: pw.FlexColumnWidth(1.2),
    4: pw.FlexColumnWidth(0.95),
    5: pw.FlexColumnWidth(1.0),
    6: pw.FlexColumnWidth(1.25),
  };

  static pw.TableRow _escalasPdfHeaderRow() {
    pw.Widget h(String s, {pw.Alignment a = pw.Alignment.centerLeft}) => _pdfCell(
          s,
          alignment: a,
          fontSize: 8,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
          maxLines: 2,
        );
    return pw.TableRow(
      decoration: pw.BoxDecoration(color: _pdfPrimary),
      children: [
        h('Data'),
        h('Nº escala', a: pw.Alignment.center),
        h('Serviço / plantão'),
        h('Horas (d | n)', a: pw.Alignment.center),
        h('Valor', a: pw.Alignment.centerRight),
        h('Status', a: pw.Alignment.center),
        h('Obs.'),
      ],
    );
  }

  static pw.TableRow _escalasPdfDataRow(List<String> cells) {
    return pw.TableRow(
      children: [
        _pdfCell(cells[0], maxLines: 2),
        _pdfCell(
          cells[1].isEmpty ? '—' : cells[1],
          alignment: pw.Alignment.center,
          maxLines: 3,
        ),
        _pdfCell(cells[2], maxLines: 5),
        _pdfCell(cells[3], alignment: pw.Alignment.center, maxLines: 2),
        _pdfCell(cells[4], alignment: pw.Alignment.centerRight, maxLines: 1),
        _pdfCell(cells[5], alignment: pw.Alignment.center, maxLines: 2),
        _pdfCell(cells[6].isEmpty ? '—' : cells[6], maxLines: 5),
      ],
    );
  }

  static List<List<String>> _escalasPdfMapRows(List<Map<String, dynamic>> escalas) {
    return escalas.map((e) {
      final valor = (e['valor'] ?? '').toString();
      final horasRaw = (e['horasCompacta'] ?? e['horasLinha'] ?? e['horasResumo'] ?? '-').toString().trim();
      final horasTxt = sanitizeForReport(horasRaw);
      return [
        sanitizeForReport((e['data'] ?? '').toString()),
        sanitizeForReport((e['numeroEscala'] ?? '').toString()),
        sanitizeForReport((e['compromisso'] ?? '').toString()),
        horasTxt.isEmpty ? '—' : horasTxt,
        valor.isEmpty ? 'R\$ 0,00' : valor,
        sanitizeForReport((e['status'] ?? '').toString()),
        sanitizeForReport((e['observacao'] ?? '').toString()),
      ];
    }).toList();
  }

  static pw.Widget _buildEscalasTableWidget(List<Map<String, dynamic>> escalas) {
    final dataRows = _escalasPdfMapRows(escalas);
    return _wrapRoundedPdfSurface(
      pw.Table(
        border: pw.TableBorder(
          horizontalInside: pw.BorderSide(color: _pdfGrey300, width: 0.45),
          verticalInside: pw.BorderSide(color: _pdfGrey300, width: 0.45),
        ),
        columnWidths: _escalasPdfColumnWidths,
        children: [
          _escalasPdfHeaderRow(),
          ...dataRows.map(_escalasPdfDataRow),
        ],
      ),
    );
  }

  static pw.Widget _buildEscalasChunkedTables(List<Map<String, dynamic>> escalas) {
    if (escalas.length <= _escalasRowsPerChunk) {
      return _buildEscalasTableWidget(escalas);
    }

    final chunks = <pw.Widget>[];
    final totalChunks = (escalas.length / _escalasRowsPerChunk).ceil();
    for (var s = 0; s < escalas.length; s += _escalasRowsPerChunk) {
      final e = math.min(s + _escalasRowsPerChunk, escalas.length);
      final idx = (s / _escalasRowsPerChunk).floor() + 1;
      final slice = escalas.sublist(s, e);
      chunks.add(
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              'Lote $idx/$totalChunks',
              style: pw.TextStyle(fontSize: 8.5, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 5),
            _buildEscalasTableWidget(slice),
          ],
        ),
      );
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < chunks.length; i++) ...[
          if (i > 0) pw.SizedBox(height: 12),
          chunks[i],
        ],
      ],
    );
  }

  static Future<pw.Document> _buildEscalasPdf({
    required String periodo,
    required List<Map<String, dynamic>> escalas,
    required double totalRecebido,
    required double totalPendente,
    String? notaProximoMes,
    String? reportTitle,
    ResumoBancoHorasPdf? resumoBancoHoras,
  }) async {
    final theme = await _latinPdfTheme();
    final pdf = pw.Document(
      compress: true,
      theme: theme,
      title: reportTitle ?? 'Relatório de Escalas',
      author: 'WISDOMAPP',
      subject: periodo,
    );
    final now = DateTime.now();
    final dataGeracao =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: _kA4PageMargin,
        footer: (pw.Context ctx) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Gerado em: $dataGeracao - WISDOMAPP  |  Pág. ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey500),
            ),
          ),
        ),
        build: (pw.Context context) {
          return [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'WISDOMAPP',
                      style: pw.TextStyle(
                        fontSize: 24,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.blue900,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      reportTitle ?? 'Relatório de Escalas e Produtividade',
                      style: pw.TextStyle(
                        fontSize: 12,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                pw.Text(
                  'Período: $periodo',
                  style: pw.TextStyle(
                    fontSize: 14,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blue900,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 14),
            if (resumoBancoHoras != null) ...[
              _buildResumoBancoHorasModerno(resumoBancoHoras),
              pw.SizedBox(height: 14),
            ] else
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  _buildPdfStatCard(
                    'Já recebido',
                    CurrencyFormats.formatBRL(totalRecebido),
                    PdfColors.green700,
                  ),
                  _buildPdfStatCard(
                    'A receber',
                    CurrencyFormats.formatBRL(totalPendente),
                    PdfColors.blue700,
                  ),
                ],
              ),
            if (notaProximoMes != null && notaProximoMes.isNotEmpty) ...[
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  color: PdfColors.amber50,
                  border: pw.Border.all(color: PdfColors.amber),
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(right: 6, top: 1),
                      child: pw.Text(
                        '[!]',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.amber900),
                      ),
                    ),
                    pw.Expanded(
                      child: pw.Text(
                        sanitizeForReport(notaProximoMes),
                        style: pw.TextStyle(fontSize: 10, color: PdfColors.amber900),
                      ),
                    ),
                  ],
                ),
              ),
              pw.SizedBox(height: 16),
            ],
            pw.Text(
              'Detalhamento — horas (diurno | noturno) antes do valor',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: PdfColors.blue900,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Padrão banco de horas: 05h-22h diurno; 22h01-05h noturno. Compromissos sem financeiro também exibem horas quando lançados.',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 10),
            _buildEscalasChunkedTables(escalas),
          ];
        },
      ),
    );
    return pdf;
  }

  static const _nomeCompromissosAudiencia = 'RELATORIO AGENDA WISDOMAPP';
  static final PdfColor _pdfAgendaReceita = PdfColor.fromInt(0xFF0EA5E9);
  static final PdfColor _pdfAgendaDespesa = PdfColor.fromInt(0xFFF97316);
  static final PdfColor _pdfAgendaGoogle = PdfColor.fromInt(0xFF4285F4);

  /// Filtro do PDF da Agenda: financeiro, particular (compromissos + Google) ou todos.
  static List<Map<String, dynamic>> filterAgendaPdfRows(
    List<Map<String, dynamic>> rows,
    AgendaPdfContentFilter filter,
  ) {
    switch (filter) {
      case AgendaPdfContentFilter.financeiro:
        return rows.where((e) => e['agendaRowKind'] == 'finance').toList();
      case AgendaPdfContentFilter.particular:
        return rows.where((e) => e['agendaRowKind'] != 'finance').toList();
      case AgendaPdfContentFilter.todos:
        return rows;
    }
  }

  static String agendaPdfFilterLabel(AgendaPdfContentFilter filter) =>
      switch (filter) {
        AgendaPdfContentFilter.financeiro => 'Compromissos financeiros',
        AgendaPdfContentFilter.particular =>
          'Compromissos particulares e Google Calendar',
        AgendaPdfContentFilter.todos => 'Todos os itens da Agenda',
      };

  /// Gera bytes do PDF da Agenda (compromissos, audiências, Google e financeiro).
  static Future<(Uint8List, String)> buildRelatorioCompromissosAudienciaBytes({
    required String periodo,
    required List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> financeItems = const [],
    List<Map<String, dynamic>> googleItems = const [],
    AgendaPdfContentFilter contentFilter = AgendaPdfContentFilter.todos,
    String? suggestedFilename,
  }) async {
    final pdf = await _buildCompromissosAudienciaPdf(
      periodo: periodo,
      items: items,
      financeItems: financeItems,
      googleItems: googleItems,
      contentFilter: contentFilter,
    );
    final bytes = await _pdfDocumentToBytes(pdf);
    return (bytes, suggestedFilename ?? _nomeCompromissosAudiencia);
  }

  static DateTime _agendaPdfSortDate(Map<String, dynamic> row) {
    if (row['agendaRowKind'] == 'finance') {
      return agendaFinanceEffectiveDay(row) ?? DateTime(1970);
    }
    final v = row['date'];
    if (v is Timestamp) return DateTime(v.toDate().year, v.toDate().month, v.toDate().day);
    if (v is DateTime) return DateTime(v.year, v.month, v.day);
    return DateTime(1970);
  }

  static List<Map<String, dynamic>> _mergeAgendaPdfRows(
    List<Map<String, dynamic>> reminders,
    List<Map<String, dynamic>> financeItems, [
    List<Map<String, dynamic>> googleItems = const [],
  ]) {
    final all = <Map<String, dynamic>>[
      ...reminders.map((e) => {...e, 'agendaRowKind': 'reminder'}),
      ...financeItems.map((e) => {...e, 'agendaRowKind': 'finance'}),
      ...googleItems.map((e) => {...e, 'agendaRowKind': 'google'}),
    ];
    all.sort((a, b) {
      final cmp = _agendaPdfSortDate(a).compareTo(_agendaPdfSortDate(b));
      if (cmp != 0) return cmp;
      if (a['agendaRowKind'] == 'finance' && b['agendaRowKind'] == 'finance') {
        final ta = (a['description'] ?? a['category'] ?? '').toString();
        final tb = (b['description'] ?? b['category'] ?? '').toString();
        return ta.compareTo(tb);
      }
      return (a['time'] ?? '').toString().compareTo((b['time'] ?? '').toString());
    });
    return all;
  }

  static String _reminderDatePdf(dynamic v) {
    if (v == null) return '';
    DateTime d;
    if (v is Timestamp) d = v.toDate();
    else if (v is DateTime) d = v;
    else return v.toString();
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  /// Mesma regra da Agenda / Relatórios (PDF).
  static bool _reminderEmAbertoPdf(Map<String, dynamic> data) {
    final type = (data['type'] ?? 'compromisso').toString();
    if (type == 'audiencia') {
      if (data['done'] == true) return false;
      return (data['status'] ?? 'EM_ABERTO').toString() == 'EM_ABERTO';
    }
    return (data['done'] ?? false) != true;
  }

  static pw.Widget _pdfCell(
    String text, {
    pw.Alignment alignment = pw.Alignment.centerLeft,
    double fontSize = 8.5,
    pw.FontWeight? fontWeight,
    PdfColor? color,
    int maxLines = 12,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
      child: pw.Align(
        alignment: alignment,
        child: pw.Text(
          text,
          style: pw.TextStyle(
            fontSize: fontSize,
            fontWeight: fontWeight,
            color: color,
          ),
          maxLines: maxLines,
          softWrap: true,
        ),
      ),
    );
  }

  static Future<pw.Document> _buildCompromissosAudienciaPdf({
    required String periodo,
    required List<Map<String, dynamic>> items,
    List<Map<String, dynamic>> financeItems = const [],
    List<Map<String, dynamic>> googleItems = const [],
    AgendaPdfContentFilter contentFilter = AgendaPdfContentFilter.todos,
  }) async {
    final theme = await _latinPdfTheme();
    final merged = filterAgendaPdfRows(
      _mergeAgendaPdfRows(items, financeItems, googleItems),
      contentFilter,
    );
    final filterLabel = agendaPdfFilterLabel(contentFilter);
    final compromissosCount = merged.where((e) {
      if (e['agendaRowKind'] != 'reminder') return false;
      final t = (e['type'] ?? 'compromisso').toString();
      return t != 'audiencia';
    }).length;
    final audienciasCount = merged.where((e) => (e['type'] ?? '').toString() == 'audiencia').length;
    final googleCount = merged.where((e) => e['agendaRowKind'] == 'google').length;
    final incomeItems = merged.where((e) =>
        e['agendaRowKind'] == 'finance' &&
        (e['financeType'] ?? e['type'] ?? '').toString() == 'income');
    final expenseItems = merged.where((e) =>
        e['agendaRowKind'] == 'finance' &&
        (e['financeType'] ?? e['type'] ?? '').toString() == 'expense');
    final totalReceitas = incomeItems.fold<double>(
      0,
      (s, e) => s + ((e['amount'] ?? 0) as num).toDouble().abs(),
    );
    final totalDespesas = expenseItems.fold<double>(
      0,
      (s, e) => s + ((e['amount'] ?? 0) as num).toDouble().abs(),
    );

    final pdf = pw.Document(
      compress: true,
      theme: theme,
      title: 'Agenda WISDOMAPP',
      author: 'WISDOMAPP',
      subject: periodo,
    );
    final now = DateTime.now();
    final dataGeracao =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    pw.TableRow headerRowAgenda() {
      pw.Widget h(String s, {pw.Alignment a = pw.Alignment.centerLeft}) => _pdfCell(
            s,
            alignment: a,
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
            maxLines: 2,
          );
      return pw.TableRow(
        decoration: pw.BoxDecoration(color: _pdfPrimary),
        children: [
          h('Data'),
          h('Tipo', a: pw.Alignment.center),
          h('Título'),
          h('Horário / Valor', a: pw.Alignment.center),
          h('Situação', a: pw.Alignment.center),
          h('Detalhes / Observações'),
        ],
      );
    }

    pw.TableRow dataRowAgenda(Map<String, dynamic> e, {required bool alt}) {
      final isFinance = e['agendaRowKind'] == 'finance';
      String tipoLabel;
      String title;
      String timeOrValue;
      String sit;
      String details;
      PdfColor? tipoColor;

      if (e['agendaRowKind'] == 'google') {
        tipoLabel = 'Google';
        tipoColor = _pdfAgendaGoogle;
        title = (e['title'] ?? 'Evento Google').toString();
        final time = (e['time'] ?? '').toString();
        final end = (e['endTime'] ?? '').toString();
        timeOrValue = end.isNotEmpty && time.isNotEmpty ? '$time – $end' : (time.isEmpty ? '—' : time);
        sit = 'Calendário';
        details = (e['notes'] ?? '').toString().trim();
        if (details.isEmpty) details = 'Google Calendar';
      } else if (isFinance) {
        final isIncome = (e['financeType'] ?? e['type'] ?? '').toString() == 'income';
        tipoLabel = isIncome ? 'Receita' : 'Despesa';
        tipoColor = isIncome ? _pdfAgendaReceita : _pdfAgendaDespesa;
        final cat = (e['category'] ?? '').toString().trim();
        final desc = (e['description'] ?? e['descricao'] ?? '').toString().trim();
        title = desc.isNotEmpty
            ? desc
            : (cat.isNotEmpty ? cat : (isIncome ? 'Receita pendente' : 'Despesa pendente'));
        final amount = ((e['amount'] ?? 0) as num).toDouble().abs();
        timeOrValue = CurrencyFormats.formatBRL(amount);
        sit = 'Pendente';
        final parts = <String>[];
        if (cat.isNotEmpty) parts.add('Categoria: $cat');
        final account = (e['accountName'] ?? e['account'] ?? '').toString().trim();
        if (account.isNotEmpty) parts.add('Conta: $account');
        final notes = (e['notes'] ?? e['observacao'] ?? '').toString().trim();
        if (notes.isNotEmpty) parts.add(notes);
        details = parts.isEmpty ? 'Financeiro' : parts.join(' · ');
      } else {
        final type = (e['type'] ?? 'compromisso').toString();
        tipoLabel = type == 'audiencia' ? 'Audiência' : 'Compromisso';
        tipoColor = type == 'audiencia' ? PdfColor.fromInt(0xFF7C3AED) : _pdfAccent;
        title = type == 'audiencia' ? 'Audiência' : (e['title'] ?? 'Compromisso').toString();
        final time = (e['time'] ?? '').toString();
        timeOrValue = time.isEmpty ? '—' : time;
        final aberto = _reminderEmAbertoPdf(e);
        sit = aberto ? 'A realizar' : 'Realizado';
        details = type == 'audiencia'
            ? '${(e['numeroSei'] ?? '').toString().isNotEmpty ? "SEI: ${e['numeroSei']}" : ''} ${(e['localAudiencia'] ?? '').toString()}'.trim()
            : (e['notes'] ?? '').toString();
        if (details.isEmpty) details = '—';
      }

      final dateLabel = isFinance
          ? _reminderDatePdf(agendaFinanceEffectiveDay(e))
          : (e['agendaRowKind'] == 'google'
              ? _reminderDatePdf(e['date'])
              : _reminderDatePdf(e['date']));
      final rowBg = alt ? _pdfGrey100 : PdfColors.white;
      return pw.TableRow(
        decoration: pw.BoxDecoration(color: rowBg),
        children: [
          _pdfCell(sanitizeForReport(dateLabel)),
          _pdfCell(
            sanitizeForReport(tipoLabel),
            alignment: pw.Alignment.center,
            fontWeight: pw.FontWeight.bold,
            color: tipoColor,
            maxLines: 2,
          ),
          _pdfCell(sanitizeForReport(title), maxLines: 8),
          _pdfCell(
            sanitizeForReport(timeOrValue),
            alignment: pw.Alignment.center,
            fontWeight: isFinance ? pw.FontWeight.bold : null,
            color: isFinance ? tipoColor : null,
            maxLines: 2,
          ),
          _pdfCell(sanitizeForReport(sit), alignment: pw.Alignment.center, maxLines: 2),
          _pdfCell(sanitizeForReport(details), maxLines: 14),
        ],
      );
    }

    final tableAgenda = _wrapRoundedPdfSurface(
      pw.Table(
        border: pw.TableBorder.all(color: _pdfGrey300, width: 0.65),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.0),
          1: const pw.FlexColumnWidth(0.95),
          2: const pw.FlexColumnWidth(1.45),
          3: const pw.FlexColumnWidth(1.05),
          4: const pw.FlexColumnWidth(0.85),
          5: const pw.FlexColumnWidth(2.7),
        },
        children: [
          headerRowAgenda(),
          ...merged.asMap().entries.map(
                (entry) => dataRowAgenda(entry.value, alt: entry.key.isOdd),
              ),
        ],
      ),
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _kA4PageMargin,
        footer: _pdfFooterFinanceiroEmitido(dataGeracao),
        build: (pw.Context context) {
          return [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: pw.BoxDecoration(
                color: _pdfPrimary,
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'WISDOMAPP',
                          style: pw.TextStyle(
                            fontSize: 22,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white,
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(
                          'Relatório Agenda',
                          style: pw.TextStyle(
                            fontSize: 12,
                            color: PdfColor(0.85, 0.9, 0.95),
                          ),
                        ),
                        pw.Text(
                          filterLabel,
                          style: pw.TextStyle(
                            fontSize: 9,
                            color: PdfColor(0.75, 0.82, 0.92),
                          ),
                        ),
                      ],
                    ),
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        periodo,
                        style: pw.TextStyle(
                          fontSize: 13,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Emitido em $dataGeracao',
                        style: pw.TextStyle(
                          fontSize: 8.5,
                          color: PdfColor(0.75, 0.82, 0.92),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _buildPdfStatCard(
                  'Compromissos',
                  '$compromissosCount',
                  _pdfAccent,
                ),
                _buildPdfStatCard(
                  'Audiências',
                  '$audienciasCount',
                  PdfColor.fromInt(0xFF7C3AED),
                ),
                _buildPdfStatCard(
                  'Receitas pendentes',
                  '${incomeItems.length} · ${CurrencyFormats.formatBRL(totalReceitas)}',
                  _pdfAgendaReceita,
                ),
                _buildPdfStatCard(
                  'Despesas pendentes',
                  '${expenseItems.length} · ${CurrencyFormats.formatBRL(totalDespesas)}',
                  _pdfAgendaDespesa,
                ),
                if (googleCount > 0)
                  _buildPdfStatCard(
                    'Google Calendar',
                    '$googleCount',
                    _pdfAgendaGoogle,
                  ),
              ],
            ),
            pw.SizedBox(height: 18),
            pw.Row(
              children: [
                pw.Container(
                  width: 4,
                  height: 18,
                  decoration: pw.BoxDecoration(
                    color: _pdfAccent,
                    borderRadius: pw.BorderRadius.circular(2),
                  ),
                ),
                pw.SizedBox(width: 8),
                pw.Text(
                  'Itens do período (${merged.length})',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: _pdfPrimary,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            tableAgenda,
            if (merged.isEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 12),
                child: pw.Container(
                  width: double.infinity,
                  padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: pw.BoxDecoration(
                    color: _pdfGrey100,
                    borderRadius: pw.BorderRadius.circular(10),
                    border: pw.Border.all(color: _pdfGrey300),
                  ),
                  child: pw.Text(
                    sanitizeForReport(
                      'Nenhum compromisso, audiência ou lançamento financeiro pendente no período.',
                    ),
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: _pdfGrey700,
                      fontStyle: pw.FontStyle.italic,
                    ),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
              ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Legenda: Compromisso = agenda particular (ex.: dentista). Receita/Despesa = contas pendentes do Financeiro exibidas na Agenda.',
              style: pw.TextStyle(fontSize: 8, color: _pdfGrey700, height: 1.3),
            ),
          ];
        },
      ),
    );
    return pdf;
  }

  /// Observação padrão GO: relatório mensal contabilizado até 23h59 do último dia; 00h01–07h vai para o mês seguinte.
  static const String kNotaPadraoGoias =
      'No padrão Estado de Goiás, o relatório mensal contabiliza até o último dia às 23h59. '
      'O restante (00h00 às 07h do dia seguinte) entra no mês seguinte.';

  static const _nomeProdutividade = 'RELATORIO RESUMO WISDOMAPP';
  static const _nomeSolicitacaoFolga = 'RELATORIO RESUMO WISDOMAPP';

  /// Gera bytes do PDF de Produtividade/Ocorrências. Para preview primeiro.
  static Future<(Uint8List, String)> buildRelatorioProdutividadeOcorrenciasBytes({
    required String periodo,
    required List<Map<String, dynamic>> semFolga,
    required List<Map<String, dynamic>> usadasFolga,
    String filtro = 'todos',
    String? suggestedFilename,
  }) async {
    final pdf = await _buildProdutividadePdf(
        periodo: periodo, semFolga: semFolga, usadasFolga: usadasFolga, filtro: filtro);
    final bytes = await _pdfDocumentToBytes(pdf);
    return (bytes, suggestedFilename ?? _nomeProdutividade);
  }

  /// Gera PDF do relatório de Produtividade/Ocorrências.
  /// [semFolga] ocorrências ainda não usadas para folga; [usadasFolga] lista de { folgaDate, ocorrencias: [...] }.
  static Future<void> gerarRelatorioProdutividadeOcorrencias({
    required String periodo,
    required List<Map<String, dynamic>> semFolga,
    required List<Map<String, dynamic>> usadasFolga,
    String filtro = 'todos',
    String? suggestedFilename,
  }) async {
    final (bytes, name) = await buildRelatorioProdutividadeOcorrenciasBytes(
      periodo: periodo,
      semFolga: semFolga,
      usadasFolga: usadasFolga,
      filtro: filtro,
      suggestedFilename: suggestedFilename,
    );
    try {
      await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
    } catch (e) {
      if (e.toString().contains('MissingPluginException') ||
          e.toString().contains('printPdf') ||
          e.toString().contains('No implementation') ||
          e.toString().contains('layoutPdf')) {
        openPdfFallback(bytes, filename: name);
      } else {
        rethrow;
      }
    }
  }

  static Future<pw.Document> _buildProdutividadePdf({
    required String periodo,
    required List<Map<String, dynamic>> semFolga,
    required List<Map<String, dynamic>> usadasFolga,
    String filtro = 'todos',
  }) async {
    final theme = await _latinPdfTheme();
    final pdf = pw.Document(
      compress: true,
      theme: theme,
      title: 'Produtividade / Ocorrências',
      author: 'WISDOMAPP',
      subject: periodo,
    );
    final now = DateTime.now();
    final dataGeracao =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _kA4PageMargin,
        build: (pw.Context context) {
          final parts = <pw.Widget>[
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              decoration: pw.BoxDecoration(
                color: _pdfPrimary,
                borderRadius: pw.BorderRadius.circular(12),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'WISDOMAPP',
                        style: pw.TextStyle(
                          fontSize: 22,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.white,
                        ),
                      ),
                      pw.SizedBox(height: 4),
                      pw.Text(
                        'Relatório Produtividade / Ocorrências',
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: const PdfColor(1, 1, 1, 0.7),
                        ),
                      ),
                    ],
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: pw.BoxDecoration(
                      color: const PdfColor(1, 1, 1, 0.24),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Text(
                      periodo,
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
          ];

          if (filtro != 'usadas_folga' && semFolga.isNotEmpty) {
            parts.add(pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(
                'Ocorrências sem marcar folga',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: _pdfPrimary,
                ),
              ),
            ));
            parts.add(_buildTabelaOcorrencias(semFolga));
            parts.add(pw.SizedBox(height: 16));
          }

          if (filtro != 'sem_folga' && usadasFolga.isNotEmpty) {
            parts.add(pw.Container(
              padding: const pw.EdgeInsets.only(bottom: 6),
              child: pw.Text(
                'Ocorrências usadas para folga',
                style: pw.TextStyle(
                  fontSize: 14,
                  fontWeight: pw.FontWeight.bold,
                  color: _pdfPrimary,
                ),
              ),
            ));
            for (final grupo in usadasFolga) {
              final folgaDate = sanitizeForReport((grupo['folgaDate'] ?? '').toString());
              final diaSemana = sanitizeForReport((grupo['diaSemana'] ?? '').toString());
              final items = grupo['ocorrencias'] as List<Map<String, dynamic>>? ?? [];
              if (items.isEmpty) continue;
              parts.add(pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(
                  'Folga: $folgaDate${diaSemana.isNotEmpty ? ' ($diaSemana)' : ''}',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: _pdfGrey700,
                  ),
                ),
              ));
              parts.add(_buildTabelaOcorrencias(items));
              parts.add(pw.SizedBox(height: 12));
            }
          }

          final hasProdBody = (filtro != 'usadas_folga' && semFolga.isNotEmpty) ||
              (filtro != 'sem_folga' &&
                  usadasFolga.any((g) => ((g['ocorrencias'] as List?)?.isNotEmpty ?? false)));
          if (!hasProdBody) {
            parts.add(
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(vertical: 28, horizontal: 4),
                child: pw.Text(
                  sanitizeForReport(
                    'Nenhuma ocorrência neste relatório para o período e filtro escolhidos.',
                  ),
                  style: pw.TextStyle(fontSize: 11, color: _pdfGrey700, height: 1.35),
                ),
              ),
            );
          }

          parts.addAll([
            pw.Divider(height: 1, thickness: 1, color: _pdfGrey300),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Gerado em $dataGeracao - WISDOMAPP',
                style: pw.TextStyle(fontSize: 9, color: _pdfGrey700),
              ),
            ),
          ]);

          return parts;
        },
      ),
    );
    return pdf;
  }

  static pw.Widget _buildTabelaOcorrencias(List<Map<String, dynamic>> items) {
    String dataStr(dynamic v) {
      if (v == null) return '';
      if (v is DateTime) return '${v.day.toString().padLeft(2, '0')}/${v.month.toString().padLeft(2, '0')}/${v.year}';
      if (v is Timestamp) return dataStr(v.toDate());
      return sanitizeForReport(v.toString());
    }

    String folgaStr(Map<String, dynamic> e) {
      if (!ProdutividadeOcorrenciasPdfPartition.temFolgaMarcada(e)) return '—';
      final fd = e['folgaDate'];
      if (fd is Timestamp) return DateTimeFormats.dateBR.format(fd.toDate());
      if (fd is DateTime) return DateTimeFormats.dateBR.format(fd);
      return '—';
    }

    pw.TableRow header() {
      pw.Widget h(String s, {pw.Alignment a = pw.Alignment.centerLeft}) => _pdfCell(
            s,
            alignment: a,
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white,
            maxLines: 2,
          );
      return pw.TableRow(
        decoration: pw.BoxDecoration(color: _pdfPrimary),
        children: [
          h('Data'),
          h('Nº', a: pw.Alignment.center),
          h('Natureza'),
          h('Folga', a: pw.Alignment.center),
          h('Pts', a: pw.Alignment.center),
        ],
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: _pdfGrey300),
      columnWidths: {
        0: const pw.FlexColumnWidth(1.0),
        1: const pw.FlexColumnWidth(0.95),
        2: const pw.FlexColumnWidth(2.85),
        3: const pw.FlexColumnWidth(1.0),
        4: const pw.FlexColumnWidth(0.55),
      },
      children: [
        header(),
        ...items.map((e) {
          final numStr = sanitizeForReport((e['numeroOcorrencia'] ?? '').toString());
          return pw.TableRow(
            children: [
              _pdfCell(dataStr(e['date'])),
              _pdfCell(numStr.isEmpty ? '—' : numStr, alignment: pw.Alignment.center),
              _pdfCell(sanitizeForReport((e['naturezaLabel'] ?? '').toString()), maxLines: 10),
              _pdfCell(folgaStr(e), alignment: pw.Alignment.center, maxLines: 2),
              _pdfCell('${e['pontuacao'] ?? 0}', alignment: pw.Alignment.center, maxLines: 1),
            ],
          );
        }),
      ],
    );
  }

  /// Gera bytes do PDF de solicitação de folga (para abrir no preview com Imprimir/Compartilhar).
  static Future<(Uint8List, String)> buildRelatorioSolicitacaoFolgaBytes({
    required String dataFolga,
    required String diaSemana,
    required List<Map<String, dynamic>> ocorrencias,
    required int totalPontos,
  }) async {
    final pdf = await _buildSolicitacaoFolgaPdf(
      dataFolga: dataFolga,
      diaSemana: diaSemana,
      ocorrencias: ocorrencias,
      totalPontos: totalPontos,
    );
    final bytes = await _pdfDocumentToBytes(pdf);
    return (bytes, _nomeSolicitacaoFolga);
  }

  static Future<pw.Document> _buildSolicitacaoFolgaPdf({
    required String dataFolga,
    required String diaSemana,
    required List<Map<String, dynamic>> ocorrencias,
    required int totalPontos,
  }) async {
    final dataFolgaSafe = sanitizeForReport(dataFolga);
    final diaSemanaSafe = sanitizeForReport(diaSemana);
    final theme = await _latinPdfTheme();
    final pdf = pw.Document(
      compress: true,
      theme: theme,
      title: 'Solicitação de folga',
      author: 'WISDOMAPP',
      subject: dataFolgaSafe,
    );
    final now = DateTime.now();
    final dataGeracao =
        '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: _kA4PageMargin,
        build: (pw.Context context) {
          return [
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(vertical: 20, horizontal: 24),
              decoration: pw.BoxDecoration(
                color: _pdfPrimary,
                borderRadius: pw.BorderRadius.circular(16),
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'WISDOMAPP',
                    style: pw.TextStyle(
                      fontSize: 20,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.white,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    'Solicitação de folga por produtividade',
                    style: pw.TextStyle(
                      fontSize: 12,
                      color: const PdfColor(1, 1, 1, 0.85),
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Container(
              padding: const pw.EdgeInsets.all(16),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _pdfGrey300),
                borderRadius: pw.BorderRadius.circular(12),
                color: _pdfGrey100,
              ),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Solicito a folga referente à pontuação por produtividade operacional.',
                    style: pw.TextStyle(
                      fontSize: 12,
                      color: PdfColors.black,
                      height: 1.4,
                    ),
                  ),
                  pw.SizedBox(height: 12),
                  pw.Row(
                    children: [
                      pw.Text(
                        'Data desejada para a folga: ',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: _pdfPrimary,
                        ),
                      ),
                      pw.Text(
                        '$dataFolgaSafe ($diaSemanaSafe)',
                        style: pw.TextStyle(
                          fontSize: 12,
                          fontWeight: pw.FontWeight.bold,
                          color: PdfColors.black,
                        ),
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 8),
                  pw.Text(
                    'Total de pontos das ocorrências relacionadas: $totalPontos',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 20),
            pw.Text(
              'Ocorrências utilizadas',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
                color: _pdfPrimary,
              ),
            ),
            pw.SizedBox(height: 10),
            _buildTabelaOcorrencias(ocorrencias),
            pw.SizedBox(height: 28),
            pw.Divider(height: 1, thickness: 1, color: _pdfGrey300),
            pw.SizedBox(height: 8),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                'Gerado em $dataGeracao - WISDOMAPP',
                style: pw.TextStyle(fontSize: 9, color: _pdfGrey700),
              ),
            ),
          ];
        },
      ),
    );
    return pdf;
  }

  /// Gera PDF de solicitação de folga e abre diálogo de impressão (mantido para compatibilidade).
  static Future<void> gerarPdfSolicitacaoFolga({
    required String dataFolga,
    required String diaSemana,
    required List<Map<String, dynamic>> ocorrencias,
    required int totalPontos,
  }) async {
    final (bytes, name) = await buildRelatorioSolicitacaoFolgaBytes(
      dataFolga: dataFolga,
      diaSemana: diaSemana,
      ocorrencias: ocorrencias,
      totalPontos: totalPontos,
    );
    try {
      await Printing.layoutPdf(name: name, onLayout: (_) async => bytes);
    } catch (e) {
      if (e.toString().contains('MissingPluginException') ||
          e.toString().contains('printPdf') ||
          e.toString().contains('No implementation') ||
          e.toString().contains('layoutPdf')) {
        openPdfFallback(bytes, filename: name);
      } else {
        rethrow;
      }
    }
  }
}
