import '../constants/default_open_finance_categories.dart';

/// Heurística simples para categorizar descrições vindas de Open Finance / Pluggy.
/// Evoluir para mapa editável no Firestore ou ML depois.
class CategoryMatcher {
  CategoryMatcher._();

  /// Lista comercial / UX (Lazer, Saúde, etc.) — alinhar telas de onboarding a estes rótulos.
  static List<String> get defaultSuggestedCategories => List<String>.unmodifiable(kDefaultOpenFinanceCategories);

  /// Palavras-chave → categoria (alinhado às categorias padrão do app onde possível).
  static final List<({RegExp re, String category})> _rules = [
    (re: RegExp(r'CINEMA|INGRESSO|TEATRO|PARQUE|SHOW\b|EVENTIM|SYMPLA', caseSensitive: false), category: 'Lazer'),
    (re: RegExp(r'HOSPITAL|CLINICA|CLÍNICA|LABORATOR|DENTIST|UNIMED|AMIL|SAUDE|PSICOLOG', caseSensitive: false), category: 'Saúde'),
    (re: RegExp(r'ESCOLA|UNIVERS|FACULD|CURSO ON|ALURA|UDEMY|DUOLINGO', caseSensitive: false), category: 'Educação'),
    (re: RegExp(r'METRO|METRÔ|ONIBUS|ÔNIBUS|PASSAGEM|RODOVIAR', caseSensitive: false), category: 'Transporte'),
    (re: RegExp(r'IFOOD|UBER\s*EATS|RAPPI|ZEDELIVERY', caseSensitive: false), category: 'Alimentação'),
    (re: RegExp(r'NETFLIX|SPOTIFY|DISNEY|HBO|PRIME\s*VIDEO|PARAMOUNT', caseSensitive: false), category: 'TV / Streaming'),
    (re: RegExp(r'POSTO|SHELL|IPIRANGA|BR\s+DISTRIBUIDORA|PETROBRAS', caseSensitive: false), category: 'Combustível'),
    (re: RegExp(r'CARREFOUR|PAO\s*DE\s*ACUCAR|EXTRA|ATACADAO|ASSAI|\bSAM\b', caseSensitive: false), category: 'Supermercado'),
    (re: RegExp(r'UBER\b|99(TAXI|APP)|CABIFY|INDRIVE', caseSensitive: false), category: 'Transporte'),
    (re: RegExp(r'MARKET|MERCADO', caseSensitive: false), category: 'Alimentação'),
    (re: RegExp(r'FARMACIA|DROGASIL|DROGARI|PANVEL', caseSensitive: false), category: 'Farmácia'),
    (re: RegExp(r'ENERGIA|LIGHT|CELPE|COPEL|CPFL|ENEL', caseSensitive: false), category: 'Energia'),
    (re: RegExp(r'AGUAS|SABESP|CEDAE|CORSAN', caseSensitive: false), category: 'Água'),
    (re: RegExp(r'CONDOMINIO|IPTU', caseSensitive: false), category: 'IPTU/Condomínio'),
  ];

  /// Retorna categoria sugerida; use [fallback] quando nada casar.
  static String autoCategorize(String description, {String fallback = 'Outros'}) {
    final raw = description.trim();
    if (raw.isEmpty) return fallback;
    final norm = raw.toUpperCase();
    for (final r in _rules) {
      if (r.re.hasMatch(norm)) return r.category;
    }
    return fallback;
  }
}
