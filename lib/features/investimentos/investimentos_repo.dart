// Carteira de Investimentos — leitura/gravação no Firestore.
//
// users/{uid}/investimentos/{id}: cadastro + `movimentos` (ARRAY no próprio doc:
// abrir a carteira custa uma leitura por aplicação). Mesmo formato que o bot
// grava (`functions/investimentos_gravar.js`).
//
// Financeiro: aplicar = SAÍDA da conta; resgatar = ENTRADA — os dois com
// `isTransfer: true`, que já tira o lançamento de todo total de receitas/
// despesas/categorias (`financeForaDosTotais`) e o mantém no SALDO da conta.
// Nenhuma fórmula de saldo foi alterada. O rendimento do resgate entra como
// receita comum em «Rendimentos» (configurável em settings/investimentos).

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/finance_account.dart';
import '../../utils/finance_fora_dos_totais.dart';
import 'investimentos_calculo.dart';

class InvestimentosRepo {
  InvestimentosRepo._();
  static final InvestimentosRepo instance = InvestimentosRepo._();

  static const String categoriaMovimento = 'Investimentos';
  static const String categoriaRendimento = 'Rendimentos';

  final FirebaseFirestore _db = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> col(String uidDoc) =>
      _db.collection('users').doc(uidDoc).collection('investimentos');

  Stream<List<Investimento>> stream(String uidDoc) => col(uidDoc).snapshots().map((s) => s.docs
      .map((d) => Investimento.fromMap(d.id, d.data()))
      .toList()
    ..sort((a, b) => a.nomeExibicao.toLowerCase().compareTo(b.nomeExibicao.toLowerCase())));

  // ── Índices do BCB (6 leituras por sessão, cache de 6 h) ──────────────────

  static IndicesBcb? _indices;
  static DateTime? _indicesEm;
  static Future<IndicesBcb>? _carregando;

  Future<IndicesBcb> indices({bool forcar = false}) {
    final em = _indicesEm;
    if (!forcar && _indices != null && em != null && DateTime.now().difference(em) < const Duration(hours: 6)) {
      return Future.value(_indices);
    }
    return _carregando ??= _carregarIndices().whenComplete(() => _carregando = null);
  }

  Future<IndicesBcb> _carregarIndices() async {
    final docs = <int, Map<String, dynamic>?>{};
    await Future.wait(SeriesBcb.todas.map((s) async {
      try {
        final snap = await _db.collection('indices_bcb').doc('$s').get();
        docs[s] = snap.data();
      } catch (_) {
        docs[s] = null; // sem a série: cálculo cai no calendário/padrão
      }
    }));
    final idx = IndicesBcb.deDocs(docs);
    _indices = idx;
    _indicesEm = DateTime.now();
    return idx;
  }

  // ── Cadastro ──────────────────────────────────────────────────────────────

  String novoIdMovimento() =>
      'm${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}${math.Random().nextInt(1 << 16).toRadixString(36)}';

  Timestamp _tsDoDia(String data) {
    final d = parseIso(data)!;
    return Timestamp.fromDate(DateTime.utc(d.year, d.month, d.day, 15));
  }

  Map<String, dynamic> _lancamento({
    required String type,
    required double amount,
    required String data,
    required String contaId,
    required String descricao,
    required String invId,
    required String movId,
    required String movimento,
    bool fora = true,
    String? categoria,
  }) {
    final ts = _tsDoDia(data);
    return {
      'type': type,
      'amount': (amount * 100).round() / 100,
      'category': categoria ?? categoriaMovimento,
      'description': descricao,
      'status': 'paid',
      'date': ts,
      'paidAt': ts,
      'effectiveDate': ts,
      'financeAccountId': contaId,
      if (fora) 'isTransfer': true,
      'investimentoId': invId,
      'investimentoMovimentoId': movId,
      'investimentoMovimento': movimento,
      'origem': 'investimentos',
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  /// Cria a aplicação (com a primeira aplicação, se `valorInicial` > 0) ou
  /// atualiza só o cadastro de uma existente.
  Future<String> salvarCadastro(
    String uidDoc,
    Investimento inv, {
    double valorInicial = 0,
    String? dataInicial,
    FinanceAccount? conta,
  }) async {
    if (inv.id.isNotEmpty) {
      await col(uidDoc).doc(inv.id).set(
        {...inv.cadastroMap(), 'atualizadoEm': FieldValue.serverTimestamp()},
        SetOptions(merge: true),
      );
      return inv.id;
    }
    final ref = col(uidDoc).doc();
    final batch = _db.batch();
    final movs = <Map<String, dynamic>>[];
    if (valorInicial > 0) {
      final data = dataInicial ?? hojeBrasilia();
      final movId = novoIdMovimento();
      final tx = conta != null ? _db.collection('users').doc(uidDoc).collection('transactions').doc() : null;
      movs.add(MovimentoInvestimento(
        id: movId,
        tipo: 'aporte',
        data: data,
        valor: valorInicial,
        transacoes: tx == null ? const [] : [tx.id],
        origem: 'app',
      ).toMap());
      if (tx != null) {
        batch.set(
            tx,
            _lancamento(
              type: 'expense',
              amount: valorInicial,
              data: data,
              contaId: conta!.id,
              descricao: 'Aplicação • ${inv.nomeExibicao}',
              invId: ref.id,
              movId: movId,
              movimento: 'aplicacao',
            ));
      }
    }
    batch.set(ref, {
      ...inv.copyWith(valorAtual: inv.manual && inv.valorAtual <= 0 ? valorInicial : inv.valorAtual).cadastroMap(),
      'movimentos': movs,
      'avisosEnviados': <String>[],
      'origem': 'app',
      'criadoEm': FieldValue.serverTimestamp(),
      'atualizadoEm': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return ref.id;
  }

  /// Aplicação adicional (aporte) — saída da conta, fora dos totais.
  Future<void> aplicar(String uidDoc, Investimento inv,
      {required double valor, required String data, FinanceAccount? conta}) async {
    final ref = col(uidDoc).doc(inv.id);
    final movId = novoIdMovimento();
    final batch = _db.batch();
    final tx = conta != null ? _db.collection('users').doc(uidDoc).collection('transactions').doc() : null;
    final mov = MovimentoInvestimento(
        id: movId, tipo: 'aporte', data: data, valor: valor, transacoes: tx == null ? const [] : [tx.id], origem: 'app');
    batch.update(ref, {
      'movimentos': FieldValue.arrayUnion([mov.toMap()]),
      'ativo': true,
      if (inv.manual) 'valorAtual': FieldValue.increment(valor),
      'atualizadoEm': FieldValue.serverTimestamp(),
    });
    if (tx != null) {
      batch.set(
          tx,
          _lancamento(
            type: 'expense',
            amount: valor,
            data: data,
            contaId: conta!.id,
            descricao: 'Aplicação • ${inv.nomeExibicao}',
            invId: inv.id,
            movId: movId,
            movimento: 'aplicacao',
          ));
    }
    await batch.commit();
  }

  /// Resgate (valor LÍQUIDO que caiu na conta). `split` = [simularResgate].
  Future<({double principal, double rendimento})> resgatar(String uidDoc, Investimento inv,
      {required double valor, required String data, FinanceAccount? conta, required ResultadoResgate split}) async {
    final comoReceita = await rendimentoComoReceita(uidDoc);
    final rend = comoReceita ? (split.rendimentoLiquido * 100).round() / 100 : 0.0;
    final valorR = (valor * 100).round() / 100;
    final principal = ((valorR - rend) * 100).round() / 100;
    final movId = novoIdMovimento();
    final batch = _db.batch();
    final txCol = _db.collection('users').doc(uidDoc).collection('transactions');
    final ids = <String>[];
    if (conta != null && principal > 0) {
      final r = txCol.doc();
      ids.add(r.id);
      batch.set(
          r,
          _lancamento(
            type: 'income',
            amount: principal,
            data: data,
            contaId: conta.id,
            descricao: 'Resgate • ${inv.nomeExibicao}',
            invId: inv.id,
            movId: movId,
            movimento: 'resgate',
          ));
    }
    if (conta != null && rend > 0) {
      final r = txCol.doc();
      ids.add(r.id);
      batch.set(
          r,
          _lancamento(
            type: 'income',
            amount: rend,
            data: data,
            contaId: conta.id,
            descricao: 'Rendimento de investimento • ${inv.nomeExibicao}',
            invId: inv.id,
            movId: movId,
            movimento: 'rendimento',
            fora: false,
            categoria: categoriaRendimento,
          ));
    }
    final mov = MovimentoInvestimento(id: movId, tipo: 'resgate', data: data, valor: valorR, transacoes: ids, origem: 'app');
    batch.update(col(uidDoc).doc(inv.id), {
      'movimentos': FieldValue.arrayUnion([mov.toMap()]),
      if (inv.manual) 'valorAtual': math.max(0, inv.valorAtual - valorR),
      'atualizadoEm': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    return (principal: principal, rendimento: rend);
  }

  /// Apaga um movimento e os lançamentos dele no Financeiro.
  Future<void> excluirMovimento(String uidDoc, Investimento inv, MovimentoInvestimento mov) async {
    final batch = _db.batch();
    final restantes = inv.movimentos.where((m) => m.id != mov.id || m.data != mov.data).map((m) => m.toMap()).toList();
    batch.update(col(uidDoc).doc(inv.id), {'movimentos': restantes, 'atualizadoEm': FieldValue.serverTimestamp()});
    for (final t in mov.transacoes) {
      if (t.trim().isEmpty) continue;
      batch.delete(_db.collection('users').doc(uidDoc).collection('transactions').doc(t));
    }
    await batch.commit();
  }

  /// Exclui a aplicação. `apagarLancamentos` também remove os lançamentos
  /// de aplicação/resgate do Financeiro (o saldo da conta volta ao de antes).
  Future<void> excluir(String uidDoc, Investimento inv, {required bool apagarLancamentos}) async {
    final batch = _db.batch();
    if (apagarLancamentos) {
      for (final m in inv.movimentos) {
        for (final t in m.transacoes) {
          if (t.trim().isEmpty) continue;
          batch.delete(_db.collection('users').doc(uidDoc).collection('transactions').doc(t));
        }
      }
    }
    batch.delete(col(uidDoc).doc(inv.id));
    await batch.commit();
  }

  Future<void> atualizarValorManual(String uidDoc, Investimento inv, double valor) =>
      col(uidDoc).doc(inv.id).set({
        'valorAtual': valor,
        'valorAtualEm': hojeBrasilia(),
        'atualizadoEm': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

  // ── Configuração ──────────────────────────────────────────────────────────

  DocumentReference<Map<String, dynamic>> _settings(String uidDoc) =>
      _db.collection('users').doc(uidDoc).collection('settings').doc('investimentos');

  Future<bool> rendimentoComoReceita(String uidDoc) async {
    try {
      final s = await _settings(uidDoc).get();
      return s.data()?['rendimentoComoReceita'] != false;
    } catch (_) {
      return true;
    }
  }

  Future<void> definirRendimentoComoReceita(String uidDoc, bool v) =>
      _settings(uidDoc).set({'rendimentoComoReceita': v}, SetOptions(merge: true));

  // ── Metas ─────────────────────────────────────────────────────────────────

  /// Valor LÍQUIDO das aplicações ligadas a cada meta (metaId → valor). O
  /// progresso da meta usa a fonte `investimentos_meta_fonte.dart`
  /// (GoalProgressSources) — nada é gravado nas contribuições da meta.
  Map<String, double> liquidoPorMeta(List<Investimento> lista, IndicesBcb idx, String hoje) {
    final out = <String, double>{};
    for (final i in lista) {
      if (i.metaId.isEmpty || !i.ativo) continue;
      out[i.metaId] = (out[i.metaId] ?? 0) + posicao(i, idx, hoje).liquido;
    }
    return out;
  }

  /// Metas ativas (id → título) para o seletor do cadastro.
  Future<Map<String, String>> metasAtivas(String uidDoc) async {
    final snap = await _db.collection('users').doc(uidDoc).collection('goals').where('status', isEqualTo: 'active').get();
    return {for (final d in snap.docs) d.id: (d.data()['title'] ?? 'Meta').toString()};
  }

  /// Reserva de emergência sugerida = 6 × a média das despesas pagas dos
  /// últimos 3 meses fechados (sem pagamento de fatura/transferência/investimento).
  Future<({double mediaMensal, double sugestao})> sugestaoReservaEmergencia(String uidDoc) async {
    final agora = DateTime.now();
    final ini = DateTime(agora.year, agora.month - 3, 1);
    final fim = DateTime(agora.year, agora.month, 1);
    final snap = await _db
        .collection('users')
        .doc(uidDoc)
        .collection('transactions')
        .where('effectiveDate', isGreaterThanOrEqualTo: Timestamp.fromDate(ini))
        .where('effectiveDate', isLessThan: Timestamp.fromDate(fim))
        .get();
    var total = 0.0;
    for (final d in snap.docs) {
      final m = d.data();
      if ((m['type'] ?? '') != 'expense') continue;
      if ((m['status'] ?? 'paid').toString() != 'paid') continue;
      if (financeForaDosTotais(m)) continue;
      total += ((m['amount'] ?? 0) as num).toDouble().abs();
    }
    final media = total / 3;
    return (mediaMensal: media, sugestao: media * 6);
  }
}
