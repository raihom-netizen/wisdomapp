/// Domínios usados para gerar ícones offline (`tool/fetch_bank_brand_icons.dart`).
/// Não depende do Flutter — pode ser importado pelo script em `tool/`.
const Map<String, String> kFinanceBankFaviconHosts = {
  'bradesco': 'www.bradesco.com.br',
  'itau': 'www.itau.com.br',
  'caixa': 'www.caixa.gov.br',
  'nubank': 'www.nubank.com.br',
  'c6': 'www.c6bank.com.br',
  'santander': 'www.santander.com.br',
  'bb': 'www.bb.com.br',
  'mercadopago': 'www.mercadopago.com.br',
  'inter': 'www.bancointer.com.br',
  'sicoob': 'www.sicoob.com.br',
  'sicredi': 'www.sicredi.com.br',
  'original': 'www.original.com.br',
  'btg': 'www.btgpactual.com',
  'xp': 'www.xpi.com.br',
  'picpay': 'picpay.com',
  'stone': 'www.stone.com.br',
  'cielo': 'www.cielo.com.br',
  'pagbank': 'pagbank.com.br',
  'neon': 'neon.com.br',
  'will': 'willbank.com.br',
};

/// Miniatura embutida no app (`assets/images/bank_brands/<id>.png`, tipicamente 256 px via script de fetch).
String? financeBankBrandAssetPath(String presetId) {
  if (!kFinanceBankFaviconHosts.containsKey(presetId)) return null;
  return 'assets/images/bank_brands/$presetId.png';
}
