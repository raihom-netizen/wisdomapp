import '../data/biblical_finance_tips.dart';

/// Classificação e filtros para dicas no painel admin.
class AdminFinancialTipUtils {
  AdminFinancialTipUtils._();

  static bool isBiblical(Map<String, dynamic> d) {
    final id = (d['id'] ?? '').toString();
    final cat = (d['categoria'] ?? d['categoriaSlug'] ?? '').toString().toLowerCase();
    final ref = (d['referenciaBiblica'] ?? d['versiculo'] ?? '').toString().trim();
    final verse =
        (d['textoVersiculo'] ?? d['versiculoTexto'] ?? d['citacao'] ?? '').toString().trim();
    return cat.contains('bibl') ||
        ref.isNotEmpty ||
        verse.isNotEmpty ||
        id.startsWith('bib_');
  }

  static String? biblicalBookFromReference(String ref) {
    final t = ref.trim();
    if (t.isEmpty) return null;
    final m = RegExp(r'^(.+?)\s+\d').firstMatch(t);
    return m?.group(1)?.trim();
  }

  static String? biblicalBook(Map<String, dynamic> d) {
    return biblicalBookFromReference(
      (d['referenciaBiblica'] ?? d['versiculo'] ?? '').toString(),
    );
  }

  static bool matchesSearch(Map<String, dynamic> d, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final hay = [
      d['titulo'],
      d['descricao'],
      d['categoria'],
      d['referenciaBiblica'],
      d['versiculo'],
      d['textoVersiculo'],
      d['versiculoTexto'],
    ].whereType<Object>().map((e) => e.toString()).join(' ').toLowerCase();
    return hay.contains(q);
  }

  /// Livros bíblicos conhecidos (catálogo + lista estática).
  static List<String> biblicalBooksCatalog() {
    final books = <String>{..._staticBiblicalBooks};
    for (final t in kBiblicalFinanceTips) {
      final b = biblicalBookFromReference(t.referenciaBiblica);
      if (b != null && b.isNotEmpty) books.add(b);
    }
    final sorted = books.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  static List<String> booksFromDocs(Iterable<Map<String, dynamic>> docs) {
    final books = <String>{};
    for (final d in docs) {
      if (!isBiblical(d)) continue;
      final b = biblicalBook(d);
      if (b != null && b.isNotEmpty) books.add(b);
    }
    final sorted = books.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  static const _staticBiblicalBooks = [
    'Gênesis',
    'Êxodo',
    'Levítico',
    'Números',
    'Deuteronômio',
    'Josué',
    'Juízes',
    'Rute',
    '1 Samuel',
    '2 Samuel',
    '1 Reis',
    '2 Reis',
    '1 Crônicas',
    '2 Crônicas',
    'Esdras',
    'Neemias',
    'Ester',
    'Jó',
    'Salmos',
    'Provérbios',
    'Eclesiastes',
    'Cânticos',
    'Isaías',
    'Jeremias',
    'Lamentações',
    'Ezequiel',
    'Daniel',
    'Oseias',
    'Joel',
    'Amós',
    'Obadias',
    'Jonas',
    'Miqueias',
    'Naum',
    'Habacuque',
    'Sofonias',
    'Ageu',
    'Zacarias',
    'Malaquias',
    'Mateus',
    'Marcos',
    'Lucas',
    'João',
    'Atos',
    'Romanos',
    '1 Coríntios',
    '2 Coríntios',
    'Gálatas',
    'Efésios',
    'Filipenses',
    'Colossenses',
    '1 Tessalonicenses',
    '2 Tessalonicenses',
    '1 Timóteo',
    '2 Timóteo',
    'Tito',
    'Filemon',
    'Hebreus',
    'Tiago',
    '1 Pedro',
    '2 Pedro',
    '1 João',
    '2 João',
    '3 João',
    'Judas',
    'Apocalipse',
  ];
}
