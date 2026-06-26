import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/firestore_user_doc_id.dart';
import 'bank_notification_parser.dart';

/// Dados lidos uma vez de `config_categorias` (palavras-chave + aprendizado).
class _HintsSnapshot {
  final Map<String, String> keywordMap;
  final List<dynamic> learnedRaw;

  const _HintsSnapshot(this.keywordMap, this.learnedRaw);
}

/// Mapeia trechos da descrição (SMS) → categoria de despesa/receita.
/// Padrão em código + ajustes do usuário em `users/{uid}/settings/config_categorias`.
abstract final class SmartCategoryHintsService {
  SmartCategoryHintsService._();

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  static DocumentReference<Map<String, dynamic>> _ref(String uid) => _db
      .collection('users')
      .doc(firestoreUserDocIdForAppShell(uid))
      .collection('settings')
      .doc('config_categorias');

  /// Padrão: palavra-chave (maiúscula) → categoria.
  static const Map<String, String> kDefaultKeywordToCategory = {
    'SUPERMERCADO': 'Supermercado',
    'HIPERMERCADO': 'Supermercado',
    'ATACADAO': 'Supermercado',
    'SORVETERIA': 'Alimentação',
    'ACAITERIA': 'Alimentação',
    'PIZZA': 'Alimentação',
    'LANCHONETE': 'Alimentação',
    'RESTAURANTE': 'Alimentação',
    'SUPERMERC': 'Supermercado',
    'HIPERMERC': 'Supermercado',
    'ATACAD': 'Supermercado',
    'MERCADO': 'Supermercado',
    'PADARIA': 'Alimentação',
    'HORTIFRUT': 'Alimentação',
    'AÇOUGUE': 'Alimentação',
    'ACOUGUE': 'Alimentação',
    'FARMACIA': 'Farmácia',
    'FARMÁCIA': 'Farmácia',
    'DROGARIA': 'Farmácia',
    'GELADEIRA': 'Manutenção',
    'FRIGOR': 'Manutenção',
    'POSTO': 'Combustível',
    'ABASTEC': 'Combustível',
    'SHELL': 'Combustível',
    'IPIRANGA': 'Combustível',
    'FARMAC': 'Farmácia',
    'DROGAR': 'Farmácia',
    'UBER': 'Transporte',
    'TAXI': 'Transporte',
    '99APP': 'Transporte',
    'NETFLIX': 'TV / Streaming',
    'SPOTIFY': 'TV / Streaming',
    'SMART FIT': 'Academia',
    'ACADEMI': 'Academia',
    'CONSULTA': 'Plano de saúde',
    'MEDICO': 'Plano de saúde',
    'MÉDICO': 'Plano de saúde',
    'DENTISTA': 'Plano de saúde',
    'ESCOLA': 'Escola',
    'FACULD': 'Cursos',
    'CURSO': 'Cursos',
    'ALUGUEL': 'IPTU / Condomínio',
    'CONDOMIN': 'IPTU / Condomínio',
    'IPTU': 'IPTU / Condomínio',
    'ENERGIA': 'Energia',
    'LUZ': 'Energia',
    'AGUA': 'Água',
    'ÁGUA': 'Água',
    'GAS': 'Gás',
    'INTERNET': 'Internet',
    'TELEFONE': 'Telefone',
    'CELULAR': 'Telefone',
  };

  /// Frases comuns em linguagem natural (normalizadas sem acento na busca).
  static const List<(String phrase, String category)> kPhraseHints = [
    ('super mercado', 'Supermercado'),
    ('supermercado', 'Supermercado'),
    ('hiper mercado', 'Supermercado'),
    ('mercado', 'Supermercado'),
    ('farmacia', 'Farmácia'),
    ('drogaria', 'Farmácia'),
    ('posto gasolina', 'Combustível'),
    ('abastecimento', 'Combustível'),
    ('combustivel', 'Combustível'),
    ('uber', 'Transporte'),
    ('ifood', 'Alimentação'),
    ('restaurante', 'Alimentação'),
    ('lanchonete', 'Alimentação'),
    ('padaria', 'Alimentação'),
    ('academia', 'Academia'),
    ('netflix', 'TV / Streaming'),
    ('spotify', 'TV / Streaming'),
    ('plano de saude', 'Plano de saúde'),
    ('consulta medica', 'Plano de saúde'),
    ('cartao credito', 'Cartão'),
    ('fatura cartao', 'Cartão'),
    ('aluguel', 'IPTU / Condomínio'),
    ('condominio', 'IPTU / Condomínio'),
    ('conta de luz', 'Energia'),
    ('conta de agua', 'Água'),
  ];

  static String _normalizeSearchText(String s) {
    const accents = {
      'á': 'a', 'à': 'a', 'ã': 'a', 'â': 'a', 'ä': 'a',
      'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e',
      'í': 'i', 'ì': 'i', 'î': 'i', 'ï': 'i',
      'ó': 'o', 'ò': 'o', 'õ': 'o', 'ô': 'o', 'ö': 'o',
      'ú': 'u', 'ù': 'u', 'û': 'u', 'ü': 'u',
      'ç': 'c', 'ñ': 'n',
    };
    return s
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .split('')
        .map((c) => accents[c] ?? c)
        .join()
        .trim();
  }

  static Map<String, String> _mergeKeywordMaps(Map<String, String>? fromRemote) {
    final out = Map<String, String>.from(kDefaultKeywordToCategory);
    if (fromRemote != null) {
      for (final e in fromRemote.entries) {
        final k = e.key.toString().trim().toUpperCase();
        final v = e.value.toString().trim();
        if (k.isNotEmpty && v.isNotEmpty) out[k] = v;
      }
    }
    return out;
  }

  static const Duration _cacheTtl = Duration(minutes: 5);

  static final Map<String, ({_HintsSnapshot data, DateTime at})> _cache = {};
  static final Map<String, Future<_HintsSnapshot>> _inflight = {};

  static Future<_HintsSnapshot> _snapshotForUid(String uid) {
    final key = firestoreUserDocIdForAppShell(uid);
    final hit = _cache[key];
    final now = DateTime.now();
    if (hit != null && now.difference(hit.at) < _cacheTtl) {
      return Future<_HintsSnapshot>.value(hit.data);
    }
    return _inflight.putIfAbsent(key, () async {
      try {
        final snap = await _ref(uid).get();
        final data = snap.data();
        Map<String, String>? remote;
        final raw = data?['keywordToCategory'];
        if (raw is Map) {
          final m = <String, String>{};
          for (final e in raw.entries) {
            m[e.key.toString()] = e.value.toString();
          }
          remote = m;
        }
        final kw = _mergeKeywordMaps(remote);
        final learned = data?['learned'];
        final learnedList = learned is List ? learned : const <dynamic>[];
        final shot = _HintsSnapshot(kw, learnedList);
        _cache[key] = (data: shot, at: DateTime.now());
        return shot;
      } finally {
        _inflight.remove(key);
      }
    });
  }

  /// Invalida cache após gravar aprendizado (próxima leitura traz lista nova).
  static void invalidateHintsCache(String uid) {
    _cache.remove(firestoreUserDocIdForAppShell(uid));
  }

  static String? _pickAllowed(String cat, List<String> allowed) {
    final c = cat.trim();
    if (c.isEmpty) return null;
    if (allowed.isEmpty) return c;
    for (final a in allowed) {
      if (a.trim().toLowerCase() == c.toLowerCase()) return a.trim();
    }
    return null;
  }

  static String? _matchPhraseHints(String descNorm, List<String> allowed) {
    for (final h in kPhraseHints) {
      if (descNorm.contains(h.$1)) {
        final c = _pickAllowed(h.$2, allowed);
        if (c != null) return c;
      }
    }
    return null;
  }

  static String? _matchCategoryAsWord(String descNorm, List<String> allowed) {
    final sorted = List<String>.from(allowed)
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final c in sorted) {
      final key = _normalizeSearchText(c);
      if (key.length < 3) continue;
      final re = RegExp(r'(?:^|[\s,.;|·]+)' + RegExp.escape(key) + r'(?:$|[\s,.;|·]+)');
      if (re.hasMatch(descNorm)) return c.trim();
    }
    return null;
  }

  static String? _suggestFromSnapshot(
    _HintsSnapshot snap,
    String descricao,
    List<String> allowed,
  ) {
    final desc = descricao.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    final descNorm = _normalizeSearchText(descricao);

    final phrase = _matchPhraseHints(descNorm, allowed);
    if (phrase != null) return phrase;

    final wordCat = _matchCategoryAsWord(descNorm, allowed);
    if (wordCat != null) return wordCat;

    String? pick(String cat) => _pickAllowed(cat, allowed);

    for (final e in snap.keywordMap.entries) {
      if (desc.contains(e.key)) {
        final c = pick(e.value);
        if (c != null) return c;
      }
    }

    for (final item in snap.learnedRaw) {
      if (item is! Map) continue;
      final frag = (item['fragment'] ?? '').toString().toUpperCase().trim();
      final cat = (item['category'] ?? '').toString().trim();
      if (frag.length >= 3 && desc.contains(frag)) {
        final c = pick(cat);
        if (c != null) return c;
      }
    }

    return null;
  }

  /// Retorna a primeira categoria cuja palavra-chave está contida na [descricao].
  /// [allowed] restringe às categorias que o usuário tem na lista atual.
  /// Usa **uma** leitura Firestore por TTL (e em voo partilhada), para colagens em massa não bloquearem.
  static Future<String?> suggestCategory(
    String uid,
    String descricao,
    List<String> allowed,
  ) async {
    final polished =
        BankNotificationParser.polishSmartPasteDescription(descricao) ?? descricao;
    final snap = await _snapshotForUid(uid);
    return _suggestFromSnapshot(snap, polished, allowed);
  }

  /// Correspondência direta: categoria no texto (palavra inteira ou nome longo).
  static String? matchAllowedCategoryInDescription(String descricao, List<String> allowed) {
    if (allowed.isEmpty) return null;
    final polished =
        BankNotificationParser.polishSmartPasteDescription(descricao) ?? descricao;
    final descNorm = _normalizeSearchText(polished);
    if (descNorm.length < 2) return null;

    final phrase = _matchPhraseHints(descNorm, allowed);
    if (phrase != null) return phrase;

    final word = _matchCategoryAsWord(descNorm, allowed);
    if (word != null) return word;

    final desc = polished.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();
    final sorted = List<String>.from(allowed)..sort((a, b) => b.length.compareTo(a.length));
    for (final c in sorted) {
      final cu = c.trim().toUpperCase();
      if (cu.length < 3) continue;
      if (desc.contains(cu)) return c.trim();
    }
    return null;
  }

  /// Persiste um par aprendido (usuário confirmou categoria para esta descrição).
  static Future<void> recordLearnedMapping(
    String uid,
    String descriptionFragment,
    String category,
  ) async {
    final frag = descriptionFragment.trim().toUpperCase();
    final cat = category.trim();
    if (frag.length < 3 || cat.length < 2) return;

    await _ref(uid).set({
      'learned': FieldValue.arrayUnion([
        {'fragment': frag.length > 80 ? frag.substring(0, 80) : frag, 'category': cat},
      ]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    invalidateHintsCache(uid);
  }
}
