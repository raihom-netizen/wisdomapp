/// Links do site oficial para promoções e planos (web / e-mail / banner do app).
String buildMaintenancePromoSiteUrl({
  String? promoFirestoreId,
  String source = 'banner_manutencao',
  /// E-mail da conta no app (ex.: iOS) — a landing web pode pré-preencher o login.
  String? prefillEmail,
  /// Caminho no site (ex. `/escolha-plano`). Deve começar com `/`.
  String path = '/',
}) {
  final q = <String, String>{
    'from_app': '1',
    'source': source,
  };
  final pid = promoFirestoreId?.trim();
  if (pid != null && pid.isNotEmpty) {
    q['promo'] = pid;
  }
  final em = prefillEmail?.trim();
  if (em != null && em.isNotEmpty) {
    q['prefill_email'] = em;
  }
  var p = path.trim();
  if (p.isEmpty) p = '/';
  if (!p.startsWith('/')) p = '/$p';
  return Uri.https('wisdomapp-b9e98.web.app', p, q).toString();
}

/// Ordem: URL customizada (https) → site oficial com [promoFirestoreId] (preço da promoção) → site oficial genérico → vazio.
/// [source] distingue métricas: `banner_manutencao` (app) vs `email_promocao` (e-mail).
String resolveMaintenancePromoLaunchUrl({
  required bool useOfficialPromoSite,
  required String customUrl,
  required String promoFirestoreId,
  String source = 'banner_manutencao',
}) {
  final c = customUrl.trim();
  if (c.startsWith('http://') || c.startsWith('https://')) return c;
  final p = promoFirestoreId.trim();
  if (p.isNotEmpty) {
    return buildMaintenancePromoSiteUrl(
      promoFirestoreId: p,
      source: source,
    );
  }
  if (useOfficialPromoSite) {
    return buildMaintenancePromoSiteUrl(source: source);
  }
  return '';
}
