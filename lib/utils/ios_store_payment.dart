/// Site oficial: landing, login e informações (PIX/cartão também no app via Mercado Pago).
const String kOfficialSubscriptionWebsiteUrl = 'https://wisdomapp-b9e98.web.app/';

/// Entrada para promoções pelo banner de manutenção: o site pode ler [from_app], [source] e exibir oferta após login.
/// Ajuste a landing no site (ex.: /planos, /promo) mantendo os query params se quiser métricas.
const String kOfficialPromoLandingUrl =
    'https://wisdomapp-b9e98.web.app/?from_app=1&source=banner_manutencao';
