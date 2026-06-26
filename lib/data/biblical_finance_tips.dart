import '../services/financial_tips_catalog_service.dart';

/// Dicas financeiras com base bíblica — catálogo principal do Início WISDOMAPP.
const List<FinancialTipDisplayItem> kBiblicalFinanceTips = [
  FinancialTipDisplayItem(
    id: 'bib_proverbios_16_3',
    titulo: 'Consagre seus planos ao Senhor',
    descricao:
        'Quando você alinha metas financeiras com propósito e integridade, '
        'decide melhor onde gastar, poupar e investir. Planeje o mês com calma, '
        'registre entradas e saídas e revise semanalmente.',
    categoriaSlug: 'biblia',
    iconKey: 'menu_book',
    colorKey: 'indigo',
    ordem: 10,
    referenciaBiblica: 'Provérbios 16:3',
    textoVersiculo:
        'Consagre ao Senhor tudo o que você faz, e os seus planos serão bem-sucedidos.',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_21_20',
    titulo: 'Sabedoria guarda tesouro',
    descricao:
        'Há tesouro desejável e azeite na casa do sábio; o tolo devora tudo o que possui. '
        'Construa reserva de emergência antes de aumentar o padrão de vida.',
    categoriaSlug: 'biblia',
    iconKey: 'savings',
    colorKey: 'green',
    ordem: 20,
    referenciaBiblica: 'Provérbios 21:20',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_22_7',
    titulo: 'Cuidado com o endividamento',
    descricao:
        'O rico domina sobre o pobre, e o que toma emprestado é servo do que empresta. '
        'Evite juros altos, quite dívidas caras primeiro e só use crédito com plano de pagamento.',
    categoriaSlug: 'biblia',
    iconKey: 'warning',
    colorKey: 'red',
    ordem: 30,
    referenciaBiblica: 'Provérbios 22:7',
  ),
  FinancialTipDisplayItem(
    id: 'bib_lucas_14_28',
    titulo: 'Conte o custo antes de construir',
    descricao:
        'Qual de vós, querendo edificar uma torre, não se assenta primeiro a calcular '
        'os gastos? Antes de comprar ou contratar, simule parcelas e impacto no orçamento mensal.',
    categoriaSlug: 'biblia',
    iconKey: 'bar_chart',
    colorKey: 'blue',
    ordem: 40,
    referenciaBiblica: 'Lucas 14:28',
  ),
  FinancialTipDisplayItem(
    id: 'bib_malaquias_3_10',
    titulo: 'Primeiro o que é de Deus',
    descricao:
        'Trazei todos os dízimos à casa do tesouro. Honrar a Deus com os bens é prioridade; '
        'depois organize despesas fixas, metas e poupança com o que resta.',
    categoriaSlug: 'biblia',
    iconKey: 'account_balance',
    colorKey: 'purple',
    ordem: 50,
    referenciaBiblica: 'Malaquias 3:10',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_27_23',
    titulo: 'Conheça sua situação financeira',
    descricao:
        'Procura conhecer o estado dos teus rebanhos e inclina o coração ao teu rebanho. '
        'Revise saldos, faturas e metas toda semana — o que não se mede, não se administra.',
    categoriaSlug: 'biblia',
    iconKey: 'search',
    colorKey: 'teal',
    ordem: 60,
    referenciaBiblica: 'Provérbios 27:23',
  ),
  FinancialTipDisplayItem(
    id: 'bib_eclesiastes_11_2',
    titulo: 'Diversifique com prudência',
    descricao:
        'Reparte com sete e ainda com oito, pois não sabes que mal haverá sobre a terra. '
        'Não concentre tudo em uma única aplicação ou renda; tenha reserva líquida e metas claras.',
    categoriaSlug: 'biblia',
    iconKey: 'trending_up',
    colorKey: 'primary',
    ordem: 70,
    referenciaBiblica: 'Eclesiastes 11:2',
  ),
  FinancialTipDisplayItem(
    id: 'bib_1timoteo_6_10',
    titulo: 'Dinheiro é meio, não fim',
    descricao:
        'A raiz de todos os males é o amor ao dinheiro. Use recursos para servir, '
        'cuidar da família e cumprir propósito — sem viver para acumular ou comparar.',
    categoriaSlug: 'biblia',
    iconKey: 'shield',
    colorKey: 'orange',
    ordem: 80,
    referenciaBiblica: '1 Timóteo 6:10',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_13_11',
    titulo: 'Riqueza gradual e constante',
    descricao:
        'A riqueza de vaidade diminui, mas quem a junta pouco a pouco a aumenta. '
        'Automatize uma parte da renda para poupança e invista com disciplina, não com pressa.',
    categoriaSlug: 'biblia',
    iconKey: 'timer',
    colorKey: 'green',
    ordem: 90,
    referenciaBiblica: 'Provérbios 13:11',
  ),
  FinancialTipDisplayItem(
    id: 'bib_mateus_6_21',
    titulo: 'Onde está seu tesouro',
    descricao:
        'Onde estiver o teu tesouro, aí estará também o teu coração. '
        'Defina metas financeiras que reflitam valores — educação, família, generosidade e segurança.',
    categoriaSlug: 'biblia',
    iconKey: 'lightbulb',
    colorKey: 'indigo',
    ordem: 100,
    referenciaBiblica: 'Mateus 6:21',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_3_9_10',
    titulo: 'Honre com o primeiro fruto',
    descricao:
        'Honra ao Senhor com os teus bens e com as primícias de toda a tua renda. '
        'Ao receber salário ou receita, separe primeiro dízimos, reserva e contas essenciais.',
    categoriaSlug: 'biblia',
    iconKey: 'percent',
    colorKey: 'purple',
    ordem: 110,
    referenciaBiblica: 'Provérbios 3:9-10',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_6_6_8',
    titulo: 'Formiga: poupar no tempo certo',
    descricao:
        'Vai ter com a formiga, ó preguiçoso, considera os seus caminhos e sê sábio. '
        'Ela prepara no verão o seu mantimento. Guarde parte da renda nos meses bons para os difíceis.',
    categoriaSlug: 'biblia',
    iconKey: 'savings',
    colorKey: 'teal',
    ordem: 120,
    referenciaBiblica: 'Provérbios 6:6-8',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_15_22',
    titulo: 'Peça conselho antes de decidir',
    descricao:
        'Onde não há conselho, frustram-se os planos; mas na multidão de conselheiros eles se firmam. '
        'Converse com quem administra bem antes de grandes compras, empréstimos ou investimentos.',
    categoriaSlug: 'biblia',
    iconKey: 'menu_book',
    colorKey: 'blue',
    ordem: 130,
    referenciaBiblica: 'Provérbios 15:22',
  ),
  FinancialTipDisplayItem(
    id: 'bib_romanos_13_8',
    titulo: 'Não fique devendo a ninguém',
    descricao:
        'A ninguém devais coisa alguma, a não ser o amor. '
        'Quite compromissos no prazo, evite parcelar o que não cabe no orçamento e negocie quando necessário.',
    categoriaSlug: 'biblia',
    iconKey: 'credit_card',
    colorKey: 'red',
    ordem: 140,
    referenciaBiblica: 'Romanos 13:8',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_24_27',
    titulo: 'Prepare antes de expandir',
    descricao:
        'Prepara os teus trabalhos fora, apronta o teu campo, e então edifica a tua casa. '
        'Fortaleça reserva e fluxo de caixa antes de assumir novas despesas fixas ou upgrades.',
    categoriaSlug: 'biblia',
    iconKey: 'bar_chart',
    colorKey: 'primary',
    ordem: 150,
    referenciaBiblica: 'Provérbios 24:27',
  ),
  FinancialTipDisplayItem(
    id: 'bib_2corintios_9_7',
    titulo: 'Generosidade com alegria',
    descricao:
        'Deus ama quem dá com alegria. Inclua ajuda a quem precisa no orçamento — '
        'com planejamento, não por impulso que comprometa contas básicas.',
    categoriaSlug: 'biblia',
    iconKey: 'lightbulb',
    colorKey: 'green',
    ordem: 160,
    referenciaBiblica: '2 Coríntios 9:7',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_11_1',
    titulo: 'Peso justo nos negócios',
    descricao:
        'Balança falsa é abominação ao Senhor, mas o peso justo é o seu contentamento. '
        'Seja transparente em preços, contratos e cobranças — integridade protege reputação e finanças.',
    categoriaSlug: 'biblia',
    iconKey: 'shield',
    colorKey: 'blueGrey',
    ordem: 170,
    referenciaBiblica: 'Provérbios 11:1',
  ),
  FinancialTipDisplayItem(
    id: 'bib_filipenses_4_11_12',
    titulo: 'Contentamento e disciplina',
    descricao:
        'Aprendi a contentar-me com o que tenho. Contentamento não é parar de crescer — '
        'é viver dentro do orçamento com gratidão enquanto busca metas com sabedoria.',
    categoriaSlug: 'biblia',
    iconKey: 'timer',
    colorKey: 'purple',
    ordem: 180,
    referenciaBiblica: 'Filipenses 4:11-12',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_22_26_27',
    titulo: 'Não se comprometa por impulso',
    descricao:
        'Não estejas entre os que se comprometem, entre os que ficam por fiadores de empréstimos. '
        'Evite avalizar dívidas alheias e contratos que você não controla.',
    categoriaSlug: 'biblia',
    iconKey: 'warning',
    colorKey: 'deepOrange',
    ordem: 190,
    referenciaBiblica: 'Provérbios 22:26-27',
  ),
  FinancialTipDisplayItem(
    id: 'bib_joao_10_10',
    titulo: 'Vida plena com propósito',
    descricao:
        'Eu vim para que tenham vida e a tenham com abundância. '
        'Administrar bem liberta tempo e recursos para o que realmente importa: família, fé e serviço.',
    categoriaSlug: 'biblia',
    iconKey: 'trending_up',
    colorKey: 'teal',
    ordem: 200,
    referenciaBiblica: 'João 10:10',
  ),
  FinancialTipDisplayItem(
    id: 'bib_proverbios_28_20',
    titulo: 'Fidelidade traz prosperidade',
    descricao:
        'O homem fiel será ricamente abençoado, mas quem quer enriquecer depressa não ficará impune. '
        'Prefira ganhos honestos e consistentes a atalhos arriscados ou esquemas duvidosos.',
    categoriaSlug: 'biblia',
    iconKey: 'account_balance',
    colorKey: 'green',
    ordem: 210,
    referenciaBiblica: 'Provérbios 28:20',
  ),
];
