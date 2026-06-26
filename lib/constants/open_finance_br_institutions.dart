/// Instituições comuns no Brasil para o fluxo Open Finance (busca no app).
/// A conexão real (Pluggy/Belvo) usa o ID estável em integrações futuras.
class OpenFinanceBrInstitution {
  final String id;
  final String name;
  final List<String> searchTokens;

  const OpenFinanceBrInstitution({
    required this.id,
    required this.name,
    required this.searchTokens,
  });
}

/// IDs exibidos primeiro na lista (busca vazia) — “mais populares”.
const Set<String> kOpenFinancePopularInstitutionIds = {
  'nubank',
  'itau',
  'bradesco',
  'bb',
  'caixa',
  'santander',
  'inter',
  'c6',
};

/// Lista fixa para UX; a API do agregador define quais conectores estão disponíveis.
const List<OpenFinanceBrInstitution> kOpenFinanceBrInstitutions = [
  OpenFinanceBrInstitution(
    id: 'nubank',
    name: 'Nubank',
    searchTokens: ['nu', 'nubank', 'roxinho'],
  ),
  OpenFinanceBrInstitution(
    id: 'itau',
    name: 'Itaú Unibanco',
    searchTokens: ['itau', 'itaú', 'unibanco'],
  ),
  OpenFinanceBrInstitution(
    id: 'bradesco',
    name: 'Bradesco',
    searchTokens: ['bradesco'],
  ),
  OpenFinanceBrInstitution(
    id: 'bb',
    name: 'Banco do Brasil',
    searchTokens: ['bb', 'brasil', 'banco do brasil'],
  ),
  OpenFinanceBrInstitution(
    id: 'caixa',
    name: 'Caixa Econômica Federal',
    searchTokens: ['caixa', 'cef', 'economica', 'caixa tem'],
  ),
  OpenFinanceBrInstitution(
    id: 'santander',
    name: 'Santander',
    searchTokens: ['santander'],
  ),
  OpenFinanceBrInstitution(
    id: 'inter',
    name: 'Banco Inter',
    searchTokens: ['inter', 'banco inter', 'intermedium'],
  ),
  OpenFinanceBrInstitution(
    id: 'c6',
    name: 'C6 Bank',
    searchTokens: ['c6', 'c6 bank'],
  ),
  OpenFinanceBrInstitution(
    id: 'btg',
    name: 'BTG Pactual',
    searchTokens: ['btg', 'pactual', 'btg pactual'],
  ),
  OpenFinanceBrInstitution(
    id: 'neon',
    name: 'Neon',
    searchTokens: ['neon'],
  ),
  OpenFinanceBrInstitution(
    id: 'next',
    name: 'Next',
    searchTokens: ['next', 'banco next'],
  ),
  OpenFinanceBrInstitution(
    id: 'digio',
    name: 'Digio',
    searchTokens: ['digio'],
  ),
  OpenFinanceBrInstitution(
    id: 'mercado_pago',
    name: 'Mercado Pago',
    searchTokens: ['mercado', 'mercado pago', 'mp'],
  ),
  OpenFinanceBrInstitution(
    id: 'picpay',
    name: 'PicPay',
    searchTokens: ['picpay', 'pic pay'],
  ),
  OpenFinanceBrInstitution(
    id: 'pagbank',
    name: 'PagBank (PagSeguro)',
    searchTokens: ['pagbank', 'pag seguro', 'pagseguro'],
  ),
  OpenFinanceBrInstitution(
    id: 'stone',
    name: 'Stone',
    searchTokens: ['stone'],
  ),
  OpenFinanceBrInstitution(
    id: 'recargapay',
    name: 'RecargaPay',
    searchTokens: ['recarga', 'recargapay'],
  ),
  OpenFinanceBrInstitution(
    id: 'sicredi',
    name: 'Sicredi',
    searchTokens: ['sicredi'],
  ),
  OpenFinanceBrInstitution(
    id: 'sicoob',
    name: 'Sicoob',
    searchTokens: ['sicoob'],
  ),
  OpenFinanceBrInstitution(
    id: 'banrisul',
    name: 'Banrisul',
    searchTokens: ['banrisul'],
  ),
  OpenFinanceBrInstitution(
    id: 'xp_rico',
    name: 'XP Investimentos / Rico',
    searchTokens: ['xp', 'rico', 'investimentos'],
  ),
];
