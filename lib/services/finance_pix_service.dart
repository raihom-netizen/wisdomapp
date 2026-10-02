import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/finance_account.dart';
import '../utils/firestore_user_doc_id.dart';
import '../utils/pix_br_code.dart';

/// Uma chave de um banco, para o seletor «Receber com qual Pix?».
class PixOpcao {
  PixOpcao({
    required this.conta,
    required this.chave,
    required this.padraoDaConta,
    required this.selecionadaSozinha,
  });

  final FinanceAccount conta;
  final String chave;

  /// É a chave padrão deste banco.
  final bool padraoDaConta;

  /// É a que sai sem escolher nada (o Pix padrão do app).
  final bool selecionadaSozinha;

  String get tipo => FinancePixService.tipoDaChave(chave);
}

/// O Pix que vai sair: chave, nome do recebedor (titular) e cidade.
class FinancePixInfo {
  FinancePixInfo({
    required this.chave,
    required this.titular,
    required this.cidade,
    required this.contaId,
    required this.contaNome,
  });

  final String chave;

  /// Nome COMPLETO do titular (no código Pix o Banco Central corta em 25).
  final String titular;
  final String cidade;
  final String contaId;
  final String contaNome;

  String get tipoChave => FinancePixService.tipoDaChave(chave);
}

/// Tudo que a cobrança lê do Firestore, UMA vez por tela.
class FinancePixDados {
  FinancePixDados({required this.contas, required this.prefs});

  /// Bancos/cartões na ordem do cadastro.
  final List<FinanceAccount> contas;

  /// `settings/finance_prefs` (conta padrão, Pix padrão e cidade do Pix).
  final Map<String, dynamic> prefs;
}

/// Pix do Financeiro — port do «Meu Pix»/«Cobrar com Pix» do Controle Total
/// (Vendas), sem o módulo Vendas e sem servidor:
///
/// - as chaves ficam no CADASTRO DO BANCO (`finance_accounts.pixKey` = padrão
///   da conta e `pixKeys` = todas), como no CT;
/// - o Pix padrão do app fica em `settings/finance_prefs.pixPadrao`
///   (`{contaId, chave}`), como no CT;
/// - o QR e o copia e cola (BR Code do Banco Central) são gerados NO APARELHO
///   ([gerarPixCopiaECola]); não há link de pagamento nem baixa automática —
///   o recebimento é confirmado à mão.
/// - a cidade do recebedor (campo obrigatório do BR Code) fica em
///   `finance_prefs.pixCidade` (no CT vem do «Meu cadastro» do Vendas).
class FinancePixService {
  FinancePixService._();
  static final instance = FinancePixService._();

  FirebaseFirestore get _db => FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _prefsDoc(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('settings')
      .doc('finance_prefs');

  static String tipoDaChave(String chave) {
    final n = chavePixNormalizada(chave);
    if (n.contains('@')) return 'E-mail';
    if (n.startsWith('+')) return 'Celular';
    if (RegExp(r'^\d{11}$').hasMatch(n)) return 'CPF';
    if (RegExp(r'^\d{14}$').hasMatch(n)) return 'CNPJ';
    if (RegExp(r'^[0-9a-fA-F-]{32,36}$').hasMatch(n)) return 'Chave aleatória';
    return 'Chave';
  }

  /// CPF, CNPJ, celular, e-mail ou chave aleatória.
  static bool chaveValida(String chave) {
    final c = chave.trim();
    if (c.isEmpty) return false;
    if (RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(c)) return true;
    if (RegExp(r'^[0-9a-fA-F]{8}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{4}-?[0-9a-fA-F]{12}$').hasMatch(c)) {
      return true;
    }
    final d = c.replaceAll(RegExp(r'\D'), '');
    return const [10, 11, 13, 14].contains(d.length);
  }

  /// Conta que recebe Pix (cartão de crédito e cofre não).
  static bool recebePix(FinanceAccount a) =>
      a.productType != FinanceAccount.kCard && !a.isVaultProduct;

  Future<FinancePixDados> carregarDados(String uid) async {
    final id = firestoreUserDocIdForAppShell(uid);
    final user = _db.collection('users').doc(id);
    final results = await Future.wait([
      user.collection('finance_accounts').get(),
      _prefsDoc(uid).get(),
    ]);
    final contasSnap = results[0] as QuerySnapshot<Map<String, dynamic>>;
    final contas = contasSnap.docs.map(FinanceAccount.fromDoc).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return FinancePixDados(
      contas: contas,
      prefs: (results[1] as DocumentSnapshot<Map<String, dynamic>>).data() ??
          const <String, dynamic>{},
    );
  }

  /// Pix padrão do app: a conta e a chave que saem quando ninguém escolhe outra.
  Future<({String contaId, String chave})?> pixPadrao(String uid) async {
    final snap = await _prefsDoc(uid).get();
    return _pixPadraoDoMapa(snap.data());
  }

  static ({String contaId, String chave})? pixPadraoDosDados(FinancePixDados d) =>
      _pixPadraoDoMapa(d.prefs);

  static ({String contaId, String chave})? _pixPadraoDoMapa(Map<String, dynamic>? prefs) {
    final m = prefs?['pixPadrao'];
    if (m is! Map) return null;
    final c = (m['contaId'] ?? '').toString().trim();
    if (c.isEmpty) return null;
    return (contaId: c, chave: (m['chave'] ?? '').toString().trim());
  }

  Future<void> definirPixPadrao(String uid, String contaId, String chave) =>
      _prefsDoc(uid).set({
        'pixPadrao': {'contaId': contaId, 'chave': chave.trim()},
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  Future<void> limparPixPadrao(String uid) => _prefsDoc(uid).set({
        'pixPadrao': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  /// Cidade do recebedor (vai no código Pix; sem ela sai «BRASIL»).
  static String cidadeDosDados(FinancePixDados d) =>
      (d.prefs['pixCidade'] ?? '').toString().trim();

  Future<void> definirCidade(String uid, String cidade) => _prefsDoc(uid).set({
        'pixCidade': cidade.trim().isEmpty ? FieldValue.delete() : cidade.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  /// Todas as chaves de todos os bancos; a que sairia sozinha vem primeiro.
  static List<PixOpcao> opcoesDosDados(FinancePixDados d) {
    final atual = pixDosDados(d);
    final out = <PixOpcao>[];
    for (final c in d.contas.where(recebePix)) {
      for (final k in c.chavesPix) {
        out.add(PixOpcao(
          conta: c,
          chave: k,
          padraoDaConta: k == (c.pixKey ?? '').trim(),
          selecionadaSozinha: atual != null && atual.contaId == c.id && atual.chave == k,
        ));
      }
    }
    out.sort((a, b) => (b.selecionadaSozinha ? 1 : 0) - (a.selecionadaSozinha ? 1 : 0));
    return out;
  }

  /// Qual Pix sai. [contaId]/[chave] = escolha explícita (seletor ou o banco
  /// do lançamento); sem ela vale o PIX PADRÃO do app, depois a conta
  /// principal do Financeiro e a primeira com chave. Mesma ordem do CT.
  static FinancePixInfo? pixDosDados(FinancePixDados d,
      {String contaId = '', String chave = '', String contaSugerida = ''}) {
    final prefs = d.prefs;
    final padraoFinanceiro = (prefs['defaultFinanceAccountId'] ?? '').toString();
    final pp = _pixPadraoDoMapa(prefs);
    final ppConta = pp?.contaId ?? '';
    final ppChave = pp?.chave ?? '';
    final contas = d.contas.where((a) => recebePix(a) && a.chavesPix.isNotEmpty).toList();
    if (contas.isEmpty) return null;
    FinanceAccount? achar(bool Function(FinanceAccount) f) {
      for (final c in contas) {
        if (f(c)) return c;
      }
      return null;
    }

    final escolhida = achar((c) => contaId.isNotEmpty && c.id == contaId) ??
        achar((c) => c.id == ppConta) ??
        achar((c) => contaSugerida.isNotEmpty && c.id == contaSugerida) ??
        achar((c) => c.id == padraoFinanceiro) ??
        contas.first;
    final chaves = escolhida.chavesPix;
    final chaveFinal = chaves.contains(chave.trim())
        ? chave.trim()
        : (escolhida.id == ppConta && chaves.contains(ppChave))
            ? ppChave
            : chaves.first;
    return FinancePixInfo(
      chave: chaveFinal,
      titular: (escolhida.holderName ?? '').trim(),
      cidade: cidadeDosDados(d),
      contaId: escolhida.id,
      contaNome: escolhida.displayName,
    );
  }

  /// Copia e cola (BR Code) com o valor — gerado no aparelho.
  static String codigoPix(FinancePixInfo info, {required double valor, String descricao = ''}) =>
      gerarPixCopiaECola(
        chave: info.chave,
        nome: info.titular,
        cidade: info.cidade,
        valor: valor,
        descricao: descricao,
      );

  /// Mensagem pronta para WhatsApp/Telegram/compartilhar.
  static String mensagem({
    required FinancePixInfo info,
    required String codigo,
    required String valorFormatado,
    String descricao = '',
  }) {
    final b = StringBuffer()
      ..writeln('Pagamento via Pix: $valorFormatado')
      ..writeln(descricao.trim().isEmpty ? '' : 'Referente a: ${descricao.trim()}');
    if (info.titular.isNotEmpty) b.writeln('Recebedor: ${info.titular}');
    b
      ..writeln('Chave (${info.tipoChave}): ${info.chave}')
      ..writeln()
      ..writeln('Pix copia e cola:')
      ..writeln(codigo);
    return b.toString().replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }
}
