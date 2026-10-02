import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/user_profile.dart';
import '../utils/admin_user_search.dart';
import '../utils/firestore_reliable_read.dart';

/// Taxas do Mercado Pago usadas no Resumo do admin (mesmos valores).
const double kAdminTaxaPix = 0.0099;
const double kAdminTaxaCartao = 0.0499;

/// Um pagamento aprovado (entrada) do Mercado Pago.
class AdminPagamento {
  const AdminPagamento({
    required this.valor,
    required this.data,
    required this.pix,
    this.uid,
    this.email,
    this.plano = '',
  });

  final double valor;
  final DateTime data;
  final bool pix;
  final String? uid;
  final String? email;
  final String plano;

  double get liquido => valor * (1 - (pix ? kAdminTaxaPix : kAdminTaxaCartao));
  double get taxa => valor - liquido;

  /// Meses cobertos pelo pagamento (anual = 12…); base da receita recorrente.
  int get mesesCobertos {
    final p = plano.toLowerCase();
    if (p.contains('anual') || p.contains('annual') || p.contains('year')) {
      return 12;
    }
    if (p.contains('semestr')) return 6;
    if (p.contains('trimestr') || p.contains('quarter')) return 3;
    return 1;
  }

  static AdminPagamento? fromDoc(Map<String, dynamic> data) {
    if (data['isOutgoing'] == true) return null;
    final raw = data['raw'];
    if (raw is! Map) return null;
    final amt = raw['transaction_amount'];
    final valor = amt is num ? amt.toDouble() : 0.0;
    if (valor <= 0) return null;
    DateTime? dt;
    final top = data['dateApprovedAt'];
    if (top is Timestamp) {
      dt = top.toDate();
    } else {
      final da = raw['date_approved'];
      if (da is String) dt = DateTime.tryParse(da)?.toLocal();
      if (da is Timestamp) dt = da.toDate();
    }
    if (dt == null) return null;
    final method = (raw['payment_method_id'] ?? '').toString().toLowerCase();
    final payer = raw['payer'];
    String? email;
    if (payer is Map) {
      final e = (payer['email'] ?? '').toString().trim().toLowerCase();
      if (e.isNotEmpty) email = e;
    }
    final uid = (data['uid'] ?? data['userId'] ?? '').toString().trim();
    return AdminPagamento(
      valor: valor,
      data: dt,
      pix: method == 'pix',
      uid: uid.isEmpty ? null : uid,
      email: email ?? (data['email'] ?? '').toString().trim().toLowerCase(),
      plano: (data['plan'] ?? data['planCode'] ?? '').toString(),
    );
  }
}

/// Custo fixo mensal do app (servidor, domínio, lojas…), editável no painel.
class AdminCusto {
  const AdminCusto({required this.nome, required this.valorMensal});

  final String nome;
  final double valorMensal;

  Map<String, dynamic> toJson() => {'nome': nome, 'valorMensal': valorMensal};

  static AdminCusto? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final nome = (raw['nome'] ?? '').toString().trim();
    final v = raw['valorMensal'];
    final valor = v is num ? v.toDouble() : double.tryParse('$v') ?? 0;
    if (nome.isEmpty) return null;
    return AdminCusto(nome: nome, valorMensal: valor);
  }
}

/// Resultado por usuário pagante (receitas × despesas).
class AdminResultadoUsuario {
  AdminResultadoUsuario({
    required this.uid,
    required this.nome,
    required this.email,
    required this.plano,
    required this.pago12m,
    required this.liquido12m,
    required this.custoRateado12m,
    required this.ultimoPagamento,
    required this.vencimento,
  });

  final String uid;
  final String nome;
  final String email;
  final String plano;
  final double pago12m;
  final double liquido12m;
  final double custoRateado12m;
  final DateTime? ultimoPagamento;
  final DateTime? vencimento;

  double get resultado => liquido12m - custoRateado12m;
}

/// Números do «Painel geral» do admin — tudo calculado no cliente a partir de
/// `users` e `mp_payments` (sem function nova).
class AdminPainelGeralData {
  AdminPainelGeralData._({
    required this.geradoEm,
    required this.totalUsuarios,
    required this.novos7,
    required this.novos30,
    required this.cadastrosPorMes,
    required this.porPlano,
    required this.ativos,
    required this.emTeste,
    required this.vencendo7,
    required this.emCarencia,
    required this.bloqueados,
    required this.convenio,
    required this.equipe,
    required this.pagantes,
    required this.cortesia,
    required this.naoRenovaram,
    required this.receitaPorMes,
    required this.liquidoPorMes,
    required this.mesesLabels,
    required this.receita30,
    required this.liquido30,
    required this.pagamentos30,
    required this.receitaMesAtual,
    required this.liquidoMesAtual,
    required this.mrr,
    required this.previsao30,
    required this.previsao90,
    required this.previsaoRestoDoMes,
    required this.custos,
    required this.resultadoUsuarios,
    required this.usuariosLidos,
    required this.limiteAtingido,
    this.acessoHoje = 0,
    this.acesso7 = 0,
    this.acesso30 = 0,
    this.semRegistroAcesso = 0,
  });

  /// Último acesso do app (`users.clientTelemetry.lastPingAt`): hoje, 7 e 30 dias.
  final int acessoHoje;
  final int acesso7;
  final int acesso30;

  /// Cadastros sem nenhum registro de acesso (versão antiga ou nunca abriram).
  final int semRegistroAcesso;

  final DateTime geradoEm;
  final int totalUsuarios;
  final int novos7;
  final int novos30;
  final List<int> cadastrosPorMes;
  final Map<String, int> porPlano;
  final int ativos;
  final int emTeste;
  final int vencendo7;
  final int emCarencia;
  final int bloqueados;
  final int convenio;
  final int equipe;

  /// Usuários com pagamento aprovado nos últimos 13 meses e licença ativa.
  final int pagantes;

  /// Premium ativo sem pagamento, sem convênio e fora do teste.
  final int cortesia;

  /// Pagaram antes, venceram nos últimos 30 dias e não renovaram.
  final int naoRenovaram;

  final List<double> receitaPorMes;
  final List<double> liquidoPorMes;
  final List<String> mesesLabels;
  final double receita30;
  final double liquido30;
  final int pagamentos30;
  final double receitaMesAtual;
  final double liquidoMesAtual;

  /// Receita recorrente mensal (só pagantes, último pagamento ÷ meses cobertos).
  final double mrr;

  /// Renovações previstas (só pagantes) cujo vencimento cai nos próximos 30/90 dias.
  final double previsao30;
  final double previsao90;

  /// Renovações previstas até o fim do mês corrente (líquido).
  final double previsaoRestoDoMes;

  final List<AdminCusto> custos;
  final List<AdminResultadoUsuario> resultadoUsuarios;
  final int usuariosLidos;
  final bool limiteAtingido;

  double get custoMensal => custos.fold(0.0, (s, c) => s + c.valorMensal);
  double get resultadoMesAtual => liquidoMesAtual - custoMensal;
  double get lucroPrevistoMes =>
      liquidoMesAtual + previsaoRestoDoMes - custoMensal;
  double get ticketMedio30 => pagamentos30 == 0 ? 0 : receita30 / pagamentos30;

  static const int limiteUsuarios = 5000;

  static Future<AdminPainelGeralData> carregar() async {
    final db = FirebaseFirestore.instance;
    final now = DateTime.now();
    final desde = DateTime(now.year - 1, now.month, 1);

    final results = await Future.wait<Object?>([
      firestoreQueryGetReliable(
        adminUsersWithEmailQuery(db.collection('users')).limit(limiteUsuarios),
      ),
      _carregarPagamentos(desde),
      carregarCustos(),
    ]);
    final usersSnap = results[0]! as QuerySnapshot<Map<String, dynamic>>;
    final pagamentos = results[1]! as List<AdminPagamento>;
    final custos = results[2]! as List<AdminCusto>;
    return calcular(
      usuarios: [
        for (final d in usersSnap.docs) MapEntry(d.id, d.data()),
      ],
      pagamentos: pagamentos,
      custos: custos,
      agora: now,
      limiteAtingido: usersSnap.docs.length >= limiteUsuarios,
    );
  }

  static Future<List<AdminPagamento>> _carregarPagamentos(DateTime desde) async {
    final col = FirebaseFirestore.instance.collection('mp_payments');
    QuerySnapshot<Map<String, dynamic>> snap;
    try {
      snap = await firestoreQueryGetReliable(
        col
            .where('status', isEqualTo: 'approved')
            .where('dateApprovedAt',
                isGreaterThanOrEqualTo: Timestamp.fromDate(desde))
            .orderBy('dateApprovedAt', descending: true)
            .limit(5000),
      );
    } catch (_) {
      snap = await firestoreQueryGetReliable(
        col.where('status', isEqualTo: 'approved').limit(3000),
      );
    }
    final out = <AdminPagamento>[];
    for (final d in snap.docs) {
      final p = AdminPagamento.fromDoc(d.data());
      if (p != null && !p.data.isBefore(desde)) out.add(p);
    }
    return out;
  }

  static DocumentReference<Map<String, dynamic>>? _custosRef() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) return null;
    // Fica no próprio cadastro do admin (regras já permitem; app_config é público).
    return FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('settings')
        .doc('admin_costs');
  }

  /// Erro da última leitura dos custos (null = leu certo). Antes a falha
  /// virava «custo R$ 0» calado e «Editar custos» gravava a lista vazia por
  /// cima dos custos reais.
  static Object? erroCustos;

  static Future<List<AdminCusto>> carregarCustos() async {
    final ref = _custosRef();
    if (ref == null) return const [];
    try {
      final snap = await ref.get().timeout(const Duration(seconds: 20));
      erroCustos = null;
      final raw = snap.data()?['itens'];
      if (raw is! List) return const [];
      return raw.map(AdminCusto.fromJson).whereType<AdminCusto>().toList();
    } catch (e) {
      erroCustos = e;
      return const [];
    }
  }

  static Future<void> salvarCustos(List<AdminCusto> custos) async {
    final ref = _custosRef();
    if (ref == null) return;
    await ref.set({
      'itens': custos.map((c) => c.toJson()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static DateTime? _data(Object? v) {
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  /// Cálculo puro (testável).
  static AdminPainelGeralData calcular({
    required List<MapEntry<String, Map<String, dynamic>>> usuarios,
    required List<AdminPagamento> pagamentos,
    required List<AdminCusto> custos,
    required DateTime agora,
    bool limiteAtingido = false,
  }) {
    final hoje = DateTime(agora.year, agora.month, agora.day);

    // ── Pagamentos por usuário ──
    final porUid = <String, List<AdminPagamento>>{};
    final porEmail = <String, List<AdminPagamento>>{};
    for (final p in pagamentos) {
      if (p.uid != null) (porUid[p.uid!] ??= []).add(p);
      final e = p.email;
      if (e != null && e.isNotEmpty) (porEmail[e] ??= []).add(p);
    }

    // ── Meses (12 até o atual) ──
    final meses = <DateTime>[
      for (var i = 11; i >= 0; i--) DateTime(agora.year, agora.month - i, 1),
    ];
    const nomesMes = [
      'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
      'jul', 'ago', 'set', 'out', 'nov', 'dez',
    ];
    final labels = [
      for (final m in meses) '${nomesMes[m.month - 1]}/${(m.year % 100).toString().padLeft(2, '0')}',
    ];
    int idxMes(DateTime d) {
      for (var i = 0; i < meses.length; i++) {
        final m = meses[i];
        if (d.year == m.year && d.month == m.month) return i;
      }
      return -1;
    }

    final receitaMes = List<double>.filled(12, 0);
    final liquidoMes = List<double>.filled(12, 0);
    var receita30 = 0.0, liquido30 = 0.0;
    var pag30 = 0;
    final corte30 = hoje.subtract(const Duration(days: 30));
    for (final p in pagamentos) {
      final i = idxMes(p.data);
      if (i >= 0) {
        receitaMes[i] += p.valor;
        liquidoMes[i] += p.liquido;
      }
      if (!p.data.isBefore(corte30)) {
        receita30 += p.valor;
        liquido30 += p.liquido;
        pag30++;
      }
    }

    // ── Usuários ──
    final cadastros = List<int>.filled(12, 0);
    final porPlano = <String, int>{};
    var novos7 = 0, novos30 = 0;
    var ativos = 0, emTeste = 0, vencendo7 = 0, carencia = 0, bloqueados = 0;
    var convenio = 0, equipe = 0, pagantes = 0, cortesia = 0, naoRenovaram = 0;
    var mrr = 0.0, prev30 = 0.0, prev90 = 0.0, prevMes = 0.0;
    var acessoHoje = 0, acesso7 = 0, acesso30 = 0, semAcesso = 0;
    final fimDoMes = DateTime(agora.year, agora.month + 1, 1)
        .subtract(const Duration(days: 1));
    final resultado = <AdminResultadoUsuario>[];
    final pagantesInfo = <MapEntry<Map<String, dynamic>, List<AdminPagamento>>>[];
    final pagantesUid = <String>[];

    for (final e in usuarios) {
      final data = e.value;
      if (!adminUserHasCompleteEmail(data)) continue;
      final role = (data['role'] ?? 'user').toString().toLowerCase();
      if (role == 'admin' ||
          role == 'master' ||
          role == 'gestor' ||
          role == 'editor_conteudo') {
        equipe++;
      }

      final tel = data['clientTelemetry'];
      final ping = tel is Map ? _data(tel['lastPingAt']) : null;
      if (ping == null) {
        semAcesso++;
      } else {
        if (!ping.isBefore(hoje)) acessoHoje++;
        if (agora.difference(ping).inDays < 7) acesso7++;
        if (agora.difference(ping).inDays < 30) acesso30++;
      }

      final criado = _data(data['createdAt']);
      if (criado != null) {
        final dias = hoje.difference(DateTime(criado.year, criado.month, criado.day)).inDays;
        if (dias < 7) novos7++;
        if (dias < 30) novos30++;
        final i = idxMes(criado);
        if (i >= 0) cadastros[i]++;
      }

      final plano = (data['plan'] ?? 'premium').toString().trim().toLowerCase();
      final rotulo = UserProfile.planDisplayLabelForFirestorePlan(plano);
      porPlano[rotulo] = (porPlano[rotulo] ?? 0) + 1;

      UserProfile? prof;
      try {
        prof = UserProfile.fromFirestoreMap(e.key, data);
      } catch (_) {
        prof = null;
      }
      final temConvenio = prof?.isPartnershipOrAssegoRetailTier ??
          (data['partnershipId'] ?? '').toString().trim().isNotEmpty;
      if (temConvenio) convenio++;

      final ativo = prof?.hasActiveLicense ?? false;
      final teste = prof?.isNewUserTrial ?? false;
      final venc = prof?.licenseExpiresAt;
      if (ativo) {
        ativos++;
      } else {
        bloqueados++;
      }
      if (prof?.isInGracePeriod == true) carencia++;
      if (venc != null) {
        final d = DateTime(venc.year, venc.month, venc.day).difference(hoje).inDays;
        if (d >= 0 && d <= 7) vencendo7++;
      }

      final email = (data['email'] ?? '').toString().trim().toLowerCase();
      final pags = <AdminPagamento>{
        ...?porUid[e.key],
        ...?porEmail[email],
      }.toList()
        ..sort((a, b) => b.data.compareTo(a.data));
      final pagou = pags.isNotEmpty;

      if (teste && !pagou) emTeste++;

      if (pagou && ativo) {
        pagantes++;
        pagantesInfo.add(MapEntry(data, pags));
        pagantesUid.add(e.key);
        final ult = pags.first;
        mrr += ult.valor / ult.mesesCobertos;
        if (venc != null) {
          final vd = DateTime(venc.year, venc.month, venc.day);
          final d = vd.difference(hoje).inDays;
          if (d >= 0 && d <= 30) prev30 += ult.valor;
          if (d >= 0 && d <= 90) prev90 += ult.valor;
          if (!vd.isBefore(hoje) && !vd.isAfter(fimDoMes)) prevMes += ult.liquido;
        }
      } else if (ativo && !teste && !temConvenio && (prof?.isPremium ?? false)) {
        cortesia++;
      }

      if (pagou && venc != null) {
        final d = hoje.difference(DateTime(venc.year, venc.month, venc.day)).inDays;
        final pagouDepois = pags.first.data.isAfter(venc);
        if (d > 0 && d <= 30 && !pagouDepois) naoRenovaram++;
      }
    }

    // ── Resultado por usuário (pagantes): líquido 12 m − custo rateado ──
    final custoMensal = custos.fold(0.0, (s, c) => s + c.valorMensal);
    final custoPorAtivo12m = ativos == 0 ? 0.0 : custoMensal * 12 / ativos;
    for (var i = 0; i < pagantesInfo.length; i++) {
      final data = pagantesInfo[i].key;
      final pags = pagantesInfo[i].value;
      resultado.add(AdminResultadoUsuario(
        uid: pagantesUid[i],
        nome: adminUserDisplayName(data),
        email: (data['email'] ?? '').toString(),
        plano: UserProfile.planDisplayLabelForFirestorePlan(
            (data['plan'] ?? '').toString()),
        pago12m: pags.fold(0.0, (s, p) => s + p.valor),
        liquido12m: pags.fold(0.0, (s, p) => s + p.liquido),
        custoRateado12m: custoPorAtivo12m,
        ultimoPagamento: pags.first.data,
        vencimento: _data(data['licenseExpiresAt']),
      ));
    }
    resultado.sort((a, b) => b.resultado.compareTo(a.resultado));

    return AdminPainelGeralData._(
      geradoEm: agora,
      totalUsuarios: ativos + bloqueados,
      novos7: novos7,
      novos30: novos30,
      cadastrosPorMes: cadastros,
      porPlano: porPlano,
      ativos: ativos,
      emTeste: emTeste,
      vencendo7: vencendo7,
      emCarencia: carencia,
      bloqueados: bloqueados,
      convenio: convenio,
      equipe: equipe,
      pagantes: pagantes,
      cortesia: cortesia,
      naoRenovaram: naoRenovaram,
      receitaPorMes: receitaMes,
      liquidoPorMes: liquidoMes,
      mesesLabels: labels,
      receita30: receita30,
      liquido30: liquido30,
      pagamentos30: pag30,
      receitaMesAtual: receitaMes.last,
      liquidoMesAtual: liquidoMes.last,
      mrr: mrr,
      previsao30: prev30,
      previsao90: prev90,
      previsaoRestoDoMes: prevMes,
      custos: custos,
      resultadoUsuarios: resultado,
      usuariosLidos: usuarios.length,
      limiteAtingido: limiteAtingido,
      acessoHoje: acessoHoje,
      acesso7: acesso7,
      acesso30: acesso30,
      semRegistroAcesso: semAcesso,
    );
  }
}
