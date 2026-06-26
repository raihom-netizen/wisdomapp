/// Rotas públicas usadas em FAQ, site, push e deep links.
abstract class PublicNavRoutes {
  static const String bancosSuportados = '/bancos-suportados';
}

/// Logos **locais** (offline) em `assets/images/bank_brands/{id}.png`.
///
/// Os PNG são gerados por [tool/fetch_bank_brand_icons.dart] (favicon do site da instituição,
/// tipicamente 256 px) para nítidez em ecrãs HiDPI. Os `.svg` legados na pasta são placeholders
/// opcionais; a UI de finanças usa sobretudo [pngPath].
abstract class BankBrandAssets {
  static const String _dir = 'assets/images/bank_brands/';

  /// Ficheiro PNG embutido (mesmo [id] do preset, exceto aliases abaixo).
  static String pngPath(String id) {
    if (id == 'mercado_pago') return '${_dir}mercadopago.png';
    return '$_dir$id.png';
  }

  @Deprecated('Use [pngPath] para miniaturas; SVGs na pasta são legado / placeholder.')
  static String svgPath(String id) => '$_dir$id.svg';

  /// Lista canónica para busca offline (índice em memória, sem rede).
  static const List<BankBrandOfflineEntry> offlineRegistry = [
    BankBrandOfflineEntry(id: 'nubank', displayName: 'Nubank', tokens: ['nubank', 'nu', 'roxinho', 'roxo']),
    BankBrandOfflineEntry(id: 'itau', displayName: 'Itaú', tokens: ['itau', 'itaú', '341', 'unibanco']),
    BankBrandOfflineEntry(id: 'bradesco', displayName: 'Bradesco', tokens: ['bradesco', '237']),
    BankBrandOfflineEntry(id: 'bb', displayName: 'Banco do Brasil', tokens: ['banco do brasil', 'bb', '001', 'b do brasil']),
    BankBrandOfflineEntry(id: 'santander', displayName: 'Santander', tokens: ['santander', '033']),
    BankBrandOfflineEntry(id: 'caixa', displayName: 'Caixa', tokens: ['caixa', 'cef', '104', 'caixa economica']),
    BankBrandOfflineEntry(id: 'inter', displayName: 'Inter', tokens: ['inter', '077', 'banco inter']),
    BankBrandOfflineEntry(id: 'c6', displayName: 'C6 Bank', tokens: ['c6', 'c6 bank', '336']),
    BankBrandOfflineEntry(id: 'mercado_pago', displayName: 'Mercado Pago', tokens: ['mercado pago', 'mp', 'mercadopago']),
    BankBrandOfflineEntry(id: 'picpay', displayName: 'PicPay', tokens: ['picpay', 'pic pay', '380']),
  ];

  /// Busca offline: filtra por nome ou token (rápido, O(n)).
  static List<BankBrandOfflineEntry> searchOffline(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return List<BankBrandOfflineEntry>.from(offlineRegistry);
    return offlineRegistry.where((e) {
      if (e.displayName.toLowerCase().contains(q)) return true;
      return e.tokens.any((t) => t.contains(q) || q.contains(t));
    }).toList();
  }

  static List<String> tokensFor(String id) {
    for (final e in offlineRegistry) {
      if (e.id == id) return e.tokens;
    }
    return const [];
  }
}

class BankBrandOfflineEntry {
  const BankBrandOfflineEntry({
    required this.id,
    required this.displayName,
    required this.tokens,
  });

  final String id;
  final String displayName;
  final List<String> tokens;
}
