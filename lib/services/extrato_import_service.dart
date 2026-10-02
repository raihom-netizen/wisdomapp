import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image_picker/image_picker.dart';

import '../constants/default_categories.dart';
import '../utils/extrato_import.dart';
import '../utils/finance_line_opening.dart';
import '../utils/finance_transactions_hub.dart';
import '../utils/firestore_user_doc_id.dart';
import 'finance_month_cache.dart';
import 'smart_category_hints_service.dart';
import 'smart_input_image_ocr_service.dart';
import 'smart_input_pdf_text_service.dart';
import 'user_categories_service.dart';

/// De onde o arquivo vem.
enum ExtratoOrigemArquivo { camera, galeria, arquivo }

/// O que o usuário escolheu importar.
class ExtratoArquivo {
  ExtratoArquivo({required this.nome, required this.bytes, this.caminho});
  final String nome;
  final Uint8List bytes;

  /// Caminho no disco — o ML Kit precisa dele no celular.
  final String? caminho;
}

/// Liga o leitor de extrato ao app: escolher arquivo, extrair texto,
/// classificar, achar duplicata e gravar.
///
/// Porte do `ExtratoImportService` do Controle Total. As regras de leitura
/// moram em `utils/extrato_import.dart` (Dart puro). Diferença do CT: aqui NÃO
/// existe a leitura de comprovante único por IA (`ctLerComprovante` não
/// existe no WisdomApp) — print/PDF só entram quando são extrato/fatura.
abstract final class ExtratoImportService {
  ExtratoImportService._();

  /// Extensões aceitas. PDF e imagem passam pelos leitores já existentes do
  /// app (texto do PDF / OCR); o resto é texto.
  static const List<String> extensoesAceitas = [
    'ofx', 'qfx', 'csv', 'tsv', 'txt', 'pdf', 'png', 'jpg', 'jpeg', 'webp',
  ];

  /// Teto do Firestore é 500 operações por batch; 450 deixa folga.
  static const int kPorBatch = 450;

  static CollectionReference<Map<String, dynamic>> _txRef(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(firestoreUserDocIdForAppShell(uid))
          .collection('transactions');

  // ─────────────────────────── escolher ───────────────────────────

  /// Seletor de arquivo (OFX/CSV/PDF/imagem), já com os bytes.
  static Future<ExtratoArquivo?> escolherArquivo() async {
    final r = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensoesAceitas,
      withData: true,
    );
    if (r == null || r.files.isEmpty) return null;
    final f = r.files.first;
    final bytes = f.bytes;
    if (bytes == null || bytes.isEmpty) return null;
    return ExtratoArquivo(
      nome: f.name,
      bytes: bytes,
      caminho: kIsWeb ? null : f.path,
    );
  }

  /// Print da galeria.
  static Future<ExtratoArquivo?> escolherImagem() =>
      _imagem(ImageSource.gallery, 'print.jpg');

  /// Foto na hora, pela câmera (fica no temporário, não entra na galeria).
  static Future<ExtratoArquivo?> fotografar() =>
      _imagem(ImageSource.camera, 'foto.jpg');

  static Future<ExtratoArquivo?> _imagem(ImageSource fonte, String nomePadrao) async {
    final foto = await ImagePicker().pickImage(
      source: fonte,
      imageQuality: 95,
      maxWidth: 3000,
    );
    if (foto == null) return null;
    final bytes = await foto.readAsBytes();
    if (bytes.isEmpty) return null;
    return ExtratoArquivo(
      nome: foto.name.isEmpty ? nomePadrao : foto.name,
      bytes: bytes,
      caminho: kIsWeb ? null : foto.path,
    );
  }

  // ─────────────────────────── ler ───────────────────────────

  /// Buffer → texto. Extrato brasileiro ainda sai em latin1 (OFX do Nubank
  /// declara `CHARSET:1252`); a escolha é pelo conteúdo.
  static String decodificarTexto(Uint8List bytes) {
    final tentativa = utf8.decode(bytes, allowMalformed: true);
    if (!tentativa.contains('�')) return tentativa;
    return latin1.decode(bytes, allowInvalid: true);
  }

  static bool _pareceImagem(String nome, Uint8List b) {
    final n = nome.toLowerCase();
    if (RegExp(r'\.(png|jpe?g|webp|gif|bmp)$').hasMatch(n)) return true;
    if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8) return true; // jpeg
    if (b.length >= 8 && b[0] == 0x89 && b[1] == 0x50) return true; // png
    return false;
  }

  static bool _parecePdf(String nome, Uint8List b) =>
      nome.toLowerCase().endsWith('.pdf') ||
      (b.length >= 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46);

  /// Extrai o texto de qualquer um dos formatos e interpreta. `null` quando
  /// o conteúdo não é extrato nem fatura.
  static Future<ExtratoLote?> lerArquivo(ExtratoArquivo arquivo) async {
    final texto = await extrairTexto(arquivo);
    if (texto.trim().isEmpty) return null;
    return extratoInterpretar(texto, nomeArquivo: arquivo.nome);
  }

  /// Só o texto. PDF e imagem usam os leitores que o app já tem
  /// ([SmartInputPdfTextService] / [SmartInputImageOcrService]).
  static Future<String> extrairTexto(ExtratoArquivo arquivo) async {
    if (_parecePdf(arquivo.nome, arquivo.bytes)) {
      return SmartInputPdfTextService.extractPlainText(
        arquivo.bytes,
        sourceName: arquivo.nome,
      );
    }
    if (_pareceImagem(arquivo.nome, arquivo.bytes)) {
      return SmartInputImageOcrService.recognizeFromGalleryBytes(
        bytes: arquivo.bytes,
        filePath: arquivo.caminho,
      );
    }
    return decodificarTexto(arquivo.bytes);
  }

  // ─────────────────────────── classificar ───────────────────────────

  /// Categoria de cada item, criando as que faltarem. Uma leitura das
  /// categorias no começo e as escritas só no fim.
  static Future<List<String>> classificar(String uid, ExtratoLote lote) async {
    final servico = UserCategoriesService();
    var atuais = await servico.load(uid);

    List<String> visiveis(List<String> l) =>
        l.where((c) => c != UserCategoriesService.kIncluirNova).toList();

    final universoDespesa = <String>{
      ...visiveis(atuais.expense),
      ...kDefaultExpenseCategories,
      ...SmartCategoryHintsService.kDefaultKeywordToCategory.values,
    }.toList();
    final universoReceita = <String>{
      ...visiveis(atuais.income),
      ...kDefaultIncomeCategories,
    }.toList();

    final faltandoDespesa = <String>{};
    final faltandoReceita = <String>{};

    for (final item in lote.itens) {
      final universo = item.credito ? universoReceita : universoDespesa;
      var c = SmartCategoryHintsService.matchAllowedCategoryInDescription(
        item.descricao,
        universo,
      );
      c ??= await SmartCategoryHintsService.suggestCategory(uid, item.descricao, universo);
      if (c == null || c.isEmpty) continue;
      item.categoria = c;
      final cat = c.toLowerCase();
      final tem = (item.credito ? visiveis(atuais.income) : visiveis(atuais.expense))
          .any((x) => x.toLowerCase() == cat);
      if (!tem) (item.credito ? faltandoReceita : faltandoDespesa).add(c);
    }

    final criadas = <String>[];
    for (final nome in faltandoDespesa) {
      await servico.addCustom(uid, false, nome);
      criadas.add(nome);
    }
    for (final nome in faltandoReceita) {
      await servico.addCustom(uid, true, nome);
      criadas.add(nome);
    }
    if (criadas.isNotEmpty) atuais = await servico.load(uid);

    // Sem palpite → «Outros», que precisa existir na lista do seletor.
    final semCategoria = lote.itens.where((i) => i.categoria.isEmpty).toList();
    if (semCategoria.isNotEmpty) {
      const outros = 'Outros';
      final precisaDespesa = semCategoria.any((i) => !i.credito) &&
          !visiveis(atuais.expense).any((c) => c.toLowerCase() == 'outros');
      final precisaReceita = semCategoria.any((i) => i.credito) &&
          !visiveis(atuais.income).any((c) => c.toLowerCase() == 'outros');
      if (precisaDespesa) await servico.addCustom(uid, false, outros);
      if (precisaReceita) await servico.addCustom(uid, true, outros);
      for (final i in semCategoria) {
        i.categoria = outros;
      }
    }
    return criadas;
  }

  /// Categorias para o seletor da tela de preview.
  static Future<({List<String> despesa, List<String> receita})> categoriasParaEscolha(
    String uid,
  ) async {
    final r = await UserCategoriesService().load(uid);
    List<String> limpar(List<String> l) =>
        l.where((c) => c != UserCategoriesService.kIncluirNova).toList();
    return (despesa: limpar(r.expense), receita: limpar(r.income));
  }

  // ─────────────────────────── duplicatas ───────────────────────────

  /// Marca o que já existe no período do arquivo — uma consulta só, pelo
  /// intervalo de datas. Falha na consulta (offline, índice) = segue sem
  /// marcar: melhor o usuário conferir do que a importação falhar.
  static Future<int> marcarDuplicatas(String uid, ExtratoLote lote) async {
    if (lote.itens.isEmpty) return 0;
    final datas = lote.itens.map((i) => i.data).toList()..sort();
    final de = DateTime(datas.first.year, datas.first.month, datas.first.day);
    final ate = DateTime(datas.last.year, datas.last.month, datas.last.day, 23, 59, 59);

    final existentes = <String>{};
    try {
      final snap = await _txRef(uid)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(de))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(ate))
          .limit(1000)
          .get();
      for (final d in snap.docs) {
        final t = d.data();
        final ts = t['date'];
        if (ts is! Timestamp) continue;
        existentes.add(extratoChaveDeLancamento(t, ts.toDate()));
      }
    } catch (_) {
      return 0;
    }
    return extratoMarcarRepetidos(lote.itens, existentes);
  }

  // ─────────────────────────── gravar ───────────────────────────

  /// Grava os marcados em `WriteBatch` de até [kPorBatch] documentos.
  static Future<int> gravar({
    required String uid,
    required List<ExtratoItem> itens,
    required String contaId,
    String origem = 'extrato_import',
    bool faturaDeCartao = false,
    int? diaFechamento,
  }) async {
    if (itens.isEmpty) return 0;
    final db = FirebaseFirestore.instance;
    final ref = _txRef(uid);

    for (var inicio = 0; inicio < itens.length; inicio += kPorBatch) {
      final fim = (inicio + kPorBatch) > itens.length ? itens.length : inicio + kPorBatch;
      final batch = db.batch();
      for (final i in itens.sublist(inicio, fim)) {
        final campos = extratoCamposDoLancamento(
          i,
          contaId: contaId,
          origem: origem,
          faturaDeCartao: faturaDeCartao,
          diaFechamento: diaFechamento,
        );
        final ts = Timestamp.fromDate(i.data);
        final pago = campos['status'] == 'paid';
        batch.set(ref.doc(), {
          ...campos,
          'date': ts,
          if (pago) 'paidAt': ts,
          'effectiveDate': FinanceLineOpening.effectiveTimestampForWrite(
            date: i.data,
            paidAt: pago ? ts : null,
          ),
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    }

    FinanceMonthCache.clearUid(uid);
    FinanceTransactionsHub.notifyMutated(uid: uid);

    // Aprende as classificações — solto: falha aqui não derruba a gravação.
    for (final i in itens) {
      if (i.descricao.isEmpty || i.categoria.isEmpty) continue;
      SmartCategoryHintsService.recordLearnedMapping(uid, i.descricao, i.categoria)
          .catchError((_) {});
    }
    return itens.length;
  }
}
