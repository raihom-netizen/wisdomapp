/// Normaliza descrições vindas de agregadores (Pluggy, etc.) para exibição e categorização.
///
/// Evita apagar todos os dígitos do texto (comum em ruas e nomes); remove prefixos de
/// gateway e sufixos numéricos típicos de autorização.
class TransactionNameCleaner {
  TransactionNameCleaner._();

  static final RegExp _prefixNoise = RegExp(
    r'^(PG\s*\*|PAG\*|PAGAMENTO\s+|COMPRA\s+|CARTAO\s+|CART[AÃ]O\s+|\d{4}\*{4}\d{4}\s*)',
    caseSensitive: false,
  );

  static final RegExp _tailAuthDigits = RegExp(r'[\s_\-]+\d{4,}$');
  static final RegExp _underscores = RegExp(r'_+');

  /// Ex.: `PG *MARKET_SAO_JOSE_12345` → `Market Sao Jose`.
  static String clean(String rawName) {
    var s = rawName.trim();
    if (s.isEmpty) return s;

    s = s.replaceAll(_underscores, ' ');
    s = s.replaceAll(RegExp(r'\s+'), ' ');
    s = s.replaceAll(_prefixNoise, '');
    s = s.replaceAll(_tailAuthDigits, '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return _titleCaseSingle(rawName.trim());

    return _titleCaseWords(s);
  }

  static String _titleCaseWords(String s) {
    return s
        .split(' ')
        .where((w) => w.isNotEmpty)
        .map((w) {
          final lower = w.toLowerCase();
          return '${lower[0].toUpperCase()}${lower.substring(1)}';
        })
        .join(' ');
  }

  static String _titleCaseSingle(String s) {
    if (s.isEmpty) return s;
    final lower = s.toLowerCase();
    return '${lower[0].toUpperCase()}${lower.substring(1)}';
  }
}
