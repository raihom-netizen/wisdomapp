import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fa;
import '../utils/firestore_user_doc_id.dart';

/// Um item de link útil salvo pelo usuário (serializável no Firestore).
/// Ícone e cor persistem como inteiros: iconCodePoint (IconData.codePoint) e iconColorValue (Color.value).
class LinkUtilItem {
  final String title;
  final String description;
  final String url;
  final int iconIndex;
  /// Código numérico do ícone (IconData.codePoint) — persiste no banco para não sumir ao fechar o app.
  final int? iconCodePoint;
  /// Valor da cor (Color.value) — persiste no banco.
  final int? iconColorValue;
  final List<SubLinkItem> subLinks;
  final bool isFavorite;

  const LinkUtilItem({
    required this.title,
    required this.description,
    required this.url,
    this.iconIndex = 0,
    this.iconCodePoint,
    this.iconColorValue,
    this.subLinks = const [],
    this.isFavorite = false,
  });

  Map<String, dynamic> toMap() {
    final m = <String, dynamic>{
      'title': title,
      'description': description,
      'url': url,
      'iconIndex': iconIndex,
      'subLinks': subLinks.map((s) => {'title': s.title, 'url': s.url}).toList(),
      'isFavorite': isFavorite,
    };
    if (iconCodePoint != null) m['iconCodePoint'] = iconCodePoint;
    if (iconColorValue != null) m['iconColorValue'] = iconColorValue;
    return m;
  }

  /// Firestore pode retornar num (double); converte para int de forma segura.
  static int? _toInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return (v as num).toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  static LinkUtilItem fromMap(Map<String, dynamic> map) {
    final subList = map['subLinks'];
    final subLinks = subList is List
        ? subList.map((e) {
            final m = e is Map ? Map<String, dynamic>.from(e as Map) : <String, dynamic>{};
            return SubLinkItem(
              title: (m['title'] ?? '').toString(),
              url: (m['url'] ?? '').toString(),
            );
          }).toList()
        : <SubLinkItem>[];
    return LinkUtilItem(
      title: (map['title'] ?? '').toString(),
      description: (map['description'] ?? '').toString(),
      url: (map['url'] ?? '').toString(),
      iconIndex: _toInt(map['iconIndex']) ?? 0,
      iconCodePoint: _toInt(map['iconCodePoint']),
      iconColorValue: _toInt(map['iconColorValue']),
      subLinks: subLinks,
      isFavorite: (map['isFavorite'] as bool?) ?? false,
    );
  }

  LinkUtilItem copyWith({
    String? title,
    String? description,
    String? url,
    int? iconIndex,
    int? iconCodePoint,
    int? iconColorValue,
    List<SubLinkItem>? subLinks,
    bool? isFavorite,
  }) {
    return LinkUtilItem(
      title: title ?? this.title,
      description: description ?? this.description,
      url: url ?? this.url,
      iconIndex: iconIndex ?? this.iconIndex,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
      iconColorValue: iconColorValue ?? this.iconColorValue,
      subLinks: subLinks ?? this.subLinks,
      isFavorite: isFavorite ?? this.isFavorite,
    );
  }
}

class SubLinkItem {
  final String title;
  final String url;

  const SubLinkItem({required this.title, required this.url});
}

/// Preferências de Links Úteis por usuário: users/{uid}/prefs/link_utils.
/// Lista vazia ou ausente = usa o padrão do app.
class LinkUtilsPreferenceService {
  DocumentReference<Map<String, dynamic>> _docRef(String uid) => FirebaseFirestore.instance
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('prefs')
      .doc('link_utils');

  /// Só lê com `request.auth` preenchido (caminho = [User.uid] da sessão).
  ///
  /// **Cache-first** (`get` do cache antes de `snapshots`) para a lista aparecer
  /// logo na web / PWA, alinhado ao módulo de anotações.
  Stream<List<LinkUtilItem>> stream(String uid) {
    return fa.FirebaseAuth.instance.authStateChanges().asyncExpand((user) async* {
      if (user == null) {
        yield const <LinkUtilItem>[];
        return;
      }
      final pathId = firestoreUserDocIdForAppShell(uid);
      if (pathId.isEmpty) {
        yield const <LinkUtilItem>[];
        return;
      }
      final docRef = FirebaseFirestore.instance
          .collection('users')
          .doc(pathId)
          .collection('prefs')
          .doc('link_utils');

      List<LinkUtilItem> mapDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
        if (!doc.exists) return <LinkUtilItem>[];
        final data = doc.data();
        final items = data?['items'];
        if (items is! List || items.isEmpty) return <LinkUtilItem>[];
        return items
            .map((e) =>
                LinkUtilItem.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList();
      }

      try {
        final cached =
            await docRef.get(const GetOptions(source: Source.cache));
        yield mapDoc(cached);
      } catch (_) {
        yield const <LinkUtilItem>[];
      }
      yield* docRef.snapshots().map(mapDoc);
    }).asBroadcastStream();
  }

  Future<void> save(String uid, List<LinkUtilItem> items) async {
    await _docRef(uid).set({
      'items': items.map((e) => e.toMap()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Retorna a lista padrão do app (para "Restaurar padrão" e para exibição quando usuário não tem customização).
  static List<LinkUtilItem> defaultList() {
    return LinkUtilsDefaults.items;
  }
}

/// Lista padrão de links úteis (mesma do _LinkUtil.lista + estados).
class LinkUtilsDefaults {
  static List<LinkUtilItem> get items => [
    LinkUtilItem(
      title: 'CTB Brasil',
      description: 'Consulte o Código de Trânsito Brasileiro.',
      url: 'https://www.planalto.gov.br/ccivil_03/leis/l9503compilado.htm',
      iconIndex: 0,
    ),
    LinkUtilItem(
      title: 'Gov.br',
      description: 'Acesso aos serviços e informações do governo federal.',
      url: 'https://www.gov.br',
      iconIndex: 1,
    ),
    LinkUtilItem(
      title: 'Denatran',
      description: 'Departamento Nacional de Trânsito.',
      url: 'https://www.gov.br/infraestrutura/pt-br/assuntos/transito',
      iconIndex: 2,
    ),
    LinkUtilItem(
      title: 'Débitos por estado',
      description: 'Consulte débitos de veículos por estado.',
      url: 'https://www.gov.br/infraestrutura/pt-br/assuntos/transito/conteudo-deten/divida-veicular',
      iconIndex: 3,
      subLinks: LinkUtilsDefaults.estadosBrasil,
    ),
    LinkUtilItem(
      title: 'Normas e leis',
      description: 'Acesso a legislação e normas federais.',
      url: 'https://www.planalto.gov.br/ccivil_03/leis/l_9503.htm',
      iconIndex: 4,
    ),
    LinkUtilItem(
      title: 'Calculadoras úteis',
      description: 'Ferramentas práticas para cálculos do dia a dia.',
      url: 'https://www.gov.br',
      iconIndex: 5,
    ),
    LinkUtilItem(
      title: 'Sistemas SSP-GO',
      description: 'Acesso aos sistemas da Secretaria de Segurança Pública de Goiás.',
      url: 'https://sistemas.ssp.go.gov.br/',
      iconIndex: 6,
    ),
    LinkUtilItem(
      title: 'CEDIME',
      description: 'Lei 19.969 - legislação Casa Civil Goiás.',
      url: 'https://legisla.casacivil.go.gov.br/pesquisa_legislacao/99843/lei-19969',
      iconIndex: 4,
    ),
    LinkUtilItem(
      title: 'Contra Cheque GO',
      description: 'Consulta de contracheque - folha de pagamento Goiás.',
      url: 'https://folhapagamento.sistemas.go.gov.br/folhapagamento/control?cmd=ConsContraCheque',
      iconIndex: 0,
    ),
    LinkUtilItem(
      title: 'Ficha Financeira Anual',
      description: 'Consulta da ficha financeira anual - folha de pagamento Goiás.',
      url: 'https://folhapagamento.sistemas.go.gov.br/folhapagamento/control?cmd=ConsFichaFinanceiraAnual',
      iconIndex: 0,
    ),
    LinkUtilItem(
      title: 'ASSEGO',
      description: 'Portal Assego.',
      url: 'https://assegonaopara.com.br/',
      iconIndex: 1,
    ),
    LinkUtilItem(
      title: 'ASSOF',
      description: 'Portal ASSOF.',
      url: 'https://www.assof.com.br/',
      iconIndex: 1,
    ),
    LinkUtilItem(
      title: 'ACS',
      description: 'ACSPMBM GO - portal.',
      url: 'https://www.acspmbmgo.com.br/',
      iconIndex: 1,
    ),
    LinkUtilItem(
      title: 'UNIMIL',
      description: 'Unimil Goiás - portal.',
      url: 'https://unimilgoias.com.br/',
      iconIndex: 1,
    ),
    LinkUtilItem(
      title: 'Caixa Beneficiente',
      description: 'Portal Caixa Beneficiente.',
      url: 'https://www.caixabeneficente.com.br/',
      iconIndex: 1,
    ),
    LinkUtilItem(
      title: 'Fundação Tiradentes',
      description: 'Portal da Fundação Tiradentes.',
      url: 'https://www.tiradentes.org.br/',
      iconIndex: 1,
    ),
    LinkUtilItem(
      title: 'HPMGO',
      description: 'HPM - portal.',
      url: 'https://hpm.org.br/',
      iconIndex: 1,
    ),
    LinkUtilItem(
      title: 'Recadastramento GO',
      description: 'Sistema de recadastramento - Governo de Goiás.',
      url: 'https://www.recadastramento.go.gov.br/recad/login.xhtml',
      iconIndex: 6,
    ),
  ];

  static const List<SubLinkItem> estadosBrasil = [
    SubLinkItem(title: 'Acre', url: 'https://www.ac.getran.com.br/site/apps/veiculo/consulta/filtro-consulta-veiculo.jsp'),
    SubLinkItem(title: 'Alagoas', url: 'https://ipvaonline.sefaz.al.gov.br/'),
    SubLinkItem(title: 'Amapá', url: 'https://www.detran.ap.gov.br/detranap/'),
    SubLinkItem(title: 'Amazonas', url: 'https://digital.detran.am.gov.br/'),
    SubLinkItem(title: 'Bahia', url: 'https://www.detran.ba.gov.br/'),
    SubLinkItem(title: 'Ceará', url: 'https://ipva.sefaz.ce.gov.br/'),
    SubLinkItem(title: 'Distrito Federal', url: 'https://www.detran.df.gov.br/'),
    SubLinkItem(title: 'Espírito Santo', url: 'https://detran.es.gov.br/'),
    SubLinkItem(title: 'Goiás', url: 'https://sistemas.sefaz.go.gov.br/snc/publico/ipva/form'),
    SubLinkItem(title: 'Maranhão', url: 'https://www.detran.ma.gov.br/'),
    SubLinkItem(title: 'Mato Grosso', url: 'https://www.detran.mt.gov.br/'),
    SubLinkItem(title: 'Mato Grosso do Sul', url: 'https://servicos.efazenda.ms.gov.br/ipvapublico/Home/Index'),
    SubLinkItem(title: 'Minas Gerais', url: 'https://detran.mg.gov.br/veiculos/situacao-do-veiculo/consultar-situacao-do-veiculo'),
    SubLinkItem(title: 'Pará', url: 'https://www.detran.pa.gov.br/'),
    SubLinkItem(title: 'Paraíba', url: 'https://detran.pb.gov.br/veiculos/emissao-ipva'),
    SubLinkItem(title: 'Paraná', url: 'https://www.extratodebito.detran.pr.gov.br/detranextratos/geraExtrato.do'),
    SubLinkItem(title: 'Pernambuco', url: 'https://www.detran.pe.gov.br/'),
    SubLinkItem(title: 'Piauí', url: 'https://site.detran.pi.gov.br/taxas/debitos.php'),
    SubLinkItem(title: 'Rio de Janeiro', url: 'https://www.detran.rj.gov.br/'),
    SubLinkItem(title: 'Rio Grande do Norte', url: 'https://www.detran.rn.gov.br/'),
    SubLinkItem(title: 'Rio Grande do Sul', url: 'https://www.sefaz.rs.gov.br/apps/ipva/principal/tabs/consulta'),
    SubLinkItem(title: 'Rondônia', url: 'https://www.detran.ro.gov.br/'),
    SubLinkItem(title: 'Roraima', url: 'https://www.rr.getran.com.br/site/apps/veiculo/filtroplacarenavam-consultaveiculo.jsp'),
    SubLinkItem(title: 'Santa Catarina', url: 'https://servicos.detran.sc.gov.br/veiculos'),
    SubLinkItem(title: 'São Paulo', url: 'https://operacoes.sp.gov.br/DetranWeb/'),
    SubLinkItem(title: 'Sergipe', url: 'https://www.detran.se.gov.br/'),
    SubLinkItem(title: 'Tocantins', url: 'https://www.detran.to.gov.br/'),
  ];
}
