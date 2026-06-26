import '../models/finance_tip_bank_entry.dart';

/// Definição de uma dica para Firestore (`financial_tips/{docId}`).
class FinancialTipSeedDocument {
  final String docId;
  final String titulo;
  final String descricao;
  final String categoriaSlug;
  final String iconKey;
  final String colorKey;
  final int ordem;
  final bool ativo;
  final Map<String, dynamic> condicao;

  const FinancialTipSeedDocument({
    required this.docId,
    required this.titulo,
    required this.descricao,
    required this.categoriaSlug,
    required this.iconKey,
    required this.colorKey,
    required this.ordem,
    this.ativo = true,
    this.condicao = const {'tipo': 'sempre'},
  });

  Map<String, dynamic> toFirestorePayload() => {
        'titulo': titulo,
        'descricao': descricao,
        'categoria': categoriaSlug,
        'icone': iconKey,
        'cor': colorKey,
        'iconKey': iconKey,
        'colorKey': colorKey,
        'ordem': ordem,
        'ativo': ativo,
        'condicao': condicao,
        'seedTag': 'diversificado_v2',
      };

  FinanceTipBankEntry toBankEntry() => FinanceTipBankEntry(
        id: docId,
        titulo: titulo,
        descricao: descricao,
        categoriaSlug: categoriaSlug,
        iconKey: iconKey,
        colorKey: colorKey,
      );
}

/// Banco diversificado (75 dicas): educação, comportamento, categorias e condições dinâmicas.
const List<FinancialTipSeedDocument> kFinancialTipsFirestoreSeedBank = [
  // —— Educação ——
  FinancialTipSeedDocument(
    docId: 'edu_50_30_20',
    titulo: 'Regra 50 / 30 / 20',
    descricao:
        'Referência: ~50% necessidades, 30% desejos e 20% metas/poupança. Ajuste à sua realidade — o importante é ter tetos conscientes.',
    categoriaSlug: 'educacao',
    iconKey: 'percent',
    colorKey: 'blue',
    ordem: 10,
  ),
  FinancialTipSeedDocument(
    docId: 'edu_reserve_selic',
    titulo: 'Selic, CDI e reserva',
    descricao:
        'A taxa básica influencia CDI e rendimentos de CDB/Tesouro Selic. Para emergência, priorize liquidez diária e baixo risco.',
    categoriaSlug: 'educacao',
    iconKey: 'account_balance',
    colorKey: 'indigo',
    ordem: 20,
  ),
  FinancialTipSeedDocument(
    docId: 'edu_inflation_real',
    titulo: 'Ganho real x inflação',
    descricao:
        'Rendimento só “vale” se superar a inflação do período. Compare investimentos pelo ganho real, não só o percentual nominal.',
    categoriaSlug: 'educacao',
    iconKey: 'trending_up',
    colorKey: 'teal',
    ordem: 30,
  ),
  FinancialTipSeedDocument(
    docId: 'edu_debt_snowball',
    titulo: 'Priorize juros altos',
    descricao:
        'Ao quitar dívidas, comece pelas taxas mais caras (cartão, cheque especial). Isso reduz o custo total mais rápido.',
    categoriaSlug: 'educacao',
    iconKey: 'warning',
    colorKey: 'red',
    ordem: 40,
  ),
  // —— Comportamento ——
  FinancialTipSeedDocument(
    docId: 'beh_impulse_24h',
    titulo: 'Pausa de 24 horas',
    descricao: 'Antes de comprar algo não essencial, espere um dia — boa parte das compras por impulso perde urgência.',
    categoriaSlug: 'comportamento',
    iconKey: 'timer',
    colorKey: 'orange',
    ordem: 50,
  ),
  FinancialTipSeedDocument(
    docId: 'beh_pay_yourself',
    titulo: 'Pague-se primeiro',
    descricao:
        'Separe poupança ou investimento logo ao receber, mesmo que seja um valor simbólico. O restante é para gastar com consciência.',
    categoriaSlug: 'comportamento',
    iconKey: 'savings',
    colorKey: 'green',
    ordem: 60,
  ),
  FinancialTipSeedDocument(
    docId: 'beh_deficit_alert',
    titulo: 'Gastos acima da renda',
    descricao:
        'Se as despesas do período superam as entradas, revise assinaturas, parcelas e compras a prazo antes de usar o limite do cartão.',
    categoriaSlug: 'comportamento',
    iconKey: 'warning',
    colorKey: 'red',
    ordem: 70,
    condicao: {'tipo': 'gasto_maior_receita'},
  ),
  FinancialTipSeedDocument(
    docId: 'beh_weekly_review',
    titulo: 'Revisão semanal de 10 min',
    descricao:
        'Reserve alguns minutos por semana para conferir saldo, fatura e metas. Consistência evita surpresas no fim do mês.',
    categoriaSlug: 'comportamento',
    iconKey: 'bar_chart',
    colorKey: 'indigo',
    ordem: 80,
  ),
  // —— Alimentação ——
  FinancialTipSeedDocument(
    docId: 'food_out_budget',
    titulo: 'Alimentação sob controle',
    descricao:
        'Delivery e restaurantes pesam no orçamento. Combine refeições em casa, lista de mercado e limite semanal para “comer fora”.',
    categoriaSlug: 'alimentacao',
    iconKey: 'fastfood',
    colorKey: 'red',
    ordem: 90,
    condicao: {
      'tipo': 'categoria_maior',
      'categoria': 'Alimentação',
      'valor_min': 250,
    },
  ),
  FinancialTipSeedDocument(
    docId: 'food_small_leaks',
    titulo: 'Pequenos gastos somam',
    descricao:
        'Cafés, lanches e apps de entrega parecem baratos, mas no mês viram valor alto. Uma revisão por categoria já ajuda.',
    categoriaSlug: 'alimentacao',
    iconKey: 'money_off',
    colorKey: 'deepOrange',
    ordem: 100,
    condicao: {
      'tipo': 'categoria_maior',
      'categoria': 'Alimentação',
      'valor_min': 150,
    },
  ),
  FinancialTipSeedDocument(
    docId: 'food_concentration',
    titulo: 'Alimentação domina o mês?',
    descricao:
        'Quando alimentação concentra grande parte das despesas, vale planejar cardápio e compras para reduzir desperdício.',
    categoriaSlug: 'alimentacao',
    iconKey: 'fastfood',
    colorKey: 'orange',
    ordem: 110,
    condicao: {
      'tipo': 'concentracao_categoria',
      'categoria': 'Alimentação',
      'pct_min': 28,
    },
  ),
  // —— Moradia ——
  FinancialTipSeedDocument(
    docId: 'home_fixed_costs',
    titulo: 'Custos fixos da casa',
    descricao:
        'Aluguel, condomínio, luz e internet são “base” do orçamento. Negocie planos e consumo antes de cortar variáveis pequenos.',
    categoriaSlug: 'moradia',
    iconKey: 'account_balance',
    colorKey: 'blueGrey',
    ordem: 120,
  ),
  FinancialTipSeedDocument(
    docId: 'home_emergency_buffer',
    titulo: 'Reserva para imprevistos da casa',
    descricao:
        'Reparos e manutenção aparecem sem aviso. Ter uma reserva só para moradia evita parcelar no cartão com juros.',
    categoriaSlug: 'moradia',
    iconKey: 'shield',
    colorKey: 'teal',
    ordem: 130,
  ),
  // —— Transporte ——
  FinancialTipSeedDocument(
    docId: 'trans_fuel_routes',
    titulo: 'Economize no deslocamento',
    descricao:
        'Planeje rotas, combine compromissos na mesma região e compare app de mobilidade com transporte público quando couber.',
    categoriaSlug: 'transporte',
    iconKey: 'directions_car',
    colorKey: 'blueGrey',
    ordem: 140,
    condicao: {
      'tipo': 'categoria_maior',
      'categoria': 'Transporte',
      'valor_min': 180,
    },
  ),
  FinancialTipSeedDocument(
    docId: 'trans_uber_habit',
    titulo: 'Corridas e apps',
    descricao:
        'Várias corridas curtas no mês viram centenas de reais. Para trajetos fixos, avalie mensalidade ou transporte alternativo.',
    categoriaSlug: 'transporte',
    iconKey: 'directions_car',
    colorKey: 'indigo',
    ordem: 150,
  ),
  // —— Cartão ——
  FinancialTipSeedDocument(
    docId: 'card_long_installments',
    titulo: 'Evite parcelamentos longos',
    descricao:
        'Muitas parcelas comprometem meses futuros. Prefira poucas parcelas sem juros ou compra à vista com desconto.',
    categoriaSlug: 'cartao',
    iconKey: 'credit_card',
    colorKey: 'purple',
    ordem: 160,
    condicao: {'tipo': 'gasto_maior_receita'},
  ),
  FinancialTipSeedDocument(
    docId: 'card_not_income',
    titulo: 'Cartão não é renda',
    descricao:
        'Limite disponível é dívida potencial. Use o cartão como meio de pagamento, não como extensão do salário.',
    categoriaSlug: 'cartao',
    iconKey: 'warning',
    colorKey: 'red',
    ordem: 170,
  ),
  FinancialTipSeedDocument(
    docId: 'card_invoice_date',
    titulo: 'Data de fechamento',
    descricao:
        'Compras perto do fechamento viram fatura rápido. Programe gastos maiores para logo após o pagamento da fatura.',
    categoriaSlug: 'cartao',
    iconKey: 'credit_card',
    colorKey: 'primary',
    ordem: 180,
  ),
  // —— Gastos / assinaturas ——
  FinancialTipSeedDocument(
    docId: 'exp_micro_spending',
    titulo: 'Assinaturas esquecidas',
    descricao:
        'Streaming, apps e clubes somam no ano. Cancele o que não usa e revise planos familiares duplicados.',
    categoriaSlug: 'gastos',
    iconKey: 'subscriptions',
    colorKey: 'orange',
    ordem: 190,
  ),
  FinancialTipSeedDocument(
    docId: 'exp_category_top_heavy',
    titulo: 'Concentração em uma categoria',
    descricao:
        'Quando uma categoria domina o orçamento, defina teto mensal e acompanhe semanalmente até estabilizar.',
    categoriaSlug: 'gastos',
    iconKey: 'bar_chart',
    colorKey: 'purple',
    ordem: 200,
    condicao: {
      'tipo': 'concentracao_categoria',
      'categoria': 'Outros',
      'pct_min': 35,
    },
  ),
  // —— Saúde ——
  FinancialTipSeedDocument(
    docId: 'health_plan_usage',
    titulo: 'Plano de saúde',
    descricao:
        'Use benefícios preventivos do plano e compare coparticipação em exames. Particular só quando não couber na rede.',
    categoriaSlug: 'saude',
    iconKey: 'shield',
    colorKey: 'green',
    ordem: 210,
  ),
  FinancialTipSeedDocument(
    docId: 'health_pharmacy_generic',
    titulo: 'Medicamentos e genéricos',
    descricao:
        'Compare preços entre farmácias e prefira genéricos quando o médico permitir — economia recorrente no mês.',
    categoriaSlug: 'saude',
    iconKey: 'money_off',
    colorKey: 'teal',
    ordem: 220,
  ),
  // —— Lazer ——
  FinancialTipSeedDocument(
    docId: 'leisure_budget_cap',
    titulo: 'Lazer com teto',
    descricao:
        'Lazer é importante, mas com valor máximo mensal. Assim você curte sem comprometer contas e metas.',
    categoriaSlug: 'lazer',
    iconKey: 'lightbulb',
    colorKey: 'purple',
    ordem: 230,
  ),
  // —— Investimento ——
  FinancialTipSeedDocument(
    docId: 'inv_start_early',
    titulo: 'Comece cedo, mesmo pouco',
    descricao:
        'Aportes regulares pequenos, no longo prazo, costumam superar aportes grandes esporádicos sem disciplina.',
    categoriaSlug: 'investimento',
    iconKey: 'trending_up',
    colorKey: 'green',
    ordem: 240,
  ),
  FinancialTipSeedDocument(
    docId: 'inv_emergency_fund',
    titulo: 'Reserva de emergência',
    descricao:
        'Antes de buscar rentabilidade alta, monte 3 a 6 meses de despesas essenciais em liquidez diária.',
    categoriaSlug: 'investimento',
    iconKey: 'shield',
    colorKey: 'teal',
    ordem: 250,
  ),
  FinancialTipSeedDocument(
    docId: 'inv_diversify_simple',
    titulo: 'Diversifique o básico',
    descricao:
        'Não concentre tudo em um único ativo ou emprestimo informal. Combine reserva, renda fixa e metas de longo prazo.',
    categoriaSlug: 'investimento',
    iconKey: 'account_balance',
    colorKey: 'indigo',
    ordem: 260,
  ),
  // —— Controle ——
  FinancialTipSeedDocument(
    docId: 'ctrl_track_expenses',
    titulo: 'Categorias consistentes',
    descricao:
        'Use sempre os mesmos nomes de categoria. Isso melhora gráficos, metas e dicas automáticas do assistente.',
    categoriaSlug: 'controle',
    iconKey: 'bar_chart',
    colorKey: 'indigo',
    ordem: 270,
  ),
  FinancialTipSeedDocument(
    docId: 'ctrl_fixed_review',
    titulo: 'Revise gastos fixos',
    descricao:
        'Internet, streaming, academia: negocie ou cancele o que não usa. Uma hora por trimestre pode valer centenas.',
    categoriaSlug: 'controle',
    iconKey: 'search',
    colorKey: 'blue',
    ordem: 280,
  ),
  FinancialTipSeedDocument(
    docId: 'ctrl_month_close',
    titulo: 'Fechamento do mês',
    descricao:
        'No último dia útil, compare receitas x despesas e anote um aprendizado para o mês seguinte.',
    categoriaSlug: 'controle',
    iconKey: 'menu_book',
    colorKey: 'primary',
    ordem: 290,
  ),
  // —— Metas ——
  FinancialTipSeedDocument(
    docId: 'goal_smart',
    titulo: 'Metas SMART',
    descricao:
        'Defina valor, prazo e passo mensal (ex.: viagem R\$ 3.000 em 10 meses = R\$ 300/mês). Acompanhe no módulo Metas.',
    categoriaSlug: 'metas',
    iconKey: 'savings',
    colorKey: 'green',
    ordem: 300,
  ),
  FinancialTipSeedDocument(
    docId: 'goal_separate_account',
    titulo: 'Separe por objetivo',
    descricao:
        'Conta ou “cofrinho” separado para cada meta reduz a tentação de usar o dinheiro em outra coisa.',
    categoriaSlug: 'metas',
    iconKey: 'account_balance',
    colorKey: 'blue',
    ordem: 310,
  ),
  // —— Impostos / trabalho ——
  FinancialTipSeedDocument(
    docId: 'tax_13_prepare',
    titulo: '13º e férias',
    descricao:
        'Reserve parte do 13º para impostos, dívidas caras ou reserva — evita “sumir” em compras de fim de ano.',
    categoriaSlug: 'trabalho',
    iconKey: 'percent',
    colorKey: 'orange',
    ordem: 320,
  ),
  FinancialTipSeedDocument(
    docId: 'tax_freelance_reserve',
    titulo: 'Autônomo: guarde o imposto',
    descricao:
        'Se recebe por PJ ou extras, separe percentual para DAS/IR desde o recebimento — não use tudo como renda livre.',
    categoriaSlug: 'trabalho',
    iconKey: 'warning',
    colorKey: 'deepOrange',
    ordem: 330,
  ),
  // —— Família ——
  FinancialTipSeedDocument(
    docId: 'family_talk_money',
    titulo: 'Combine em casa',
    descricao:
        'Alinhar prioridades com quem divide contas evita gastos duplicados e surpresas na fatura conjunta.',
    categoriaSlug: 'familia',
    iconKey: 'lightbulb',
    colorKey: 'primary',
    ordem: 340,
  ),
  // —— Segurança ——
  FinancialTipSeedDocument(
    docId: 'sec_pix_scams',
    titulo: 'Pix com atenção',
    descricao:
        'Confira chave e valor antes de confirmar. Desconfie de urgência e links — golpes costumam imitar bancos e lojas.',
    categoriaSlug: 'seguranca',
    iconKey: 'shield',
    colorKey: 'red',
    ordem: 350,
  ),
  FinancialTipSeedDocument(
    docId: 'sec_password_bank',
    titulo: 'Acesso ao banco',
    descricao:
        'Não compartilhe senha ou token. Ative biometria no app oficial e evite internet banking em rede pública.',
    categoriaSlug: 'seguranca',
    iconKey: 'shield',
    colorKey: 'indigo',
    ordem: 360,
  ),
  // —— Educação extra ——
  FinancialTipSeedDocument(
    docId: 'edu_compound',
    titulo: 'Juros compostos',
    descricao:
        'Rendimento sobre rendimento acelera metas longas. Começar antes e manter consistência faz grande diferença.',
    categoriaSlug: 'educacao',
    iconKey: 'trending_up',
    colorKey: 'green',
    ordem: 370,
  ),
  FinancialTipSeedDocument(
    docId: 'edu_emergency_vs_invest',
    titulo: 'Reserva antes de risco',
    descricao:
        'Sem colchão de emergência, qualquer imprevisto vira dívida cara. Só aumente risco depois da reserva mínima.',
    categoriaSlug: 'educacao',
    iconKey: 'menu_book',
    colorKey: 'teal',
    ordem: 380,
  ),
  // —— Educação (ampliado) ——
  FinancialTipSeedDocument(
    docId: 'edu_budget_zero',
    titulo: 'Orçamento base zero',
    descricao:
        'Atribua cada real a uma categoria antes do mês começar. Sobras vão para metas; faltas aparecem cedo.',
    categoriaSlug: 'educacao',
    iconKey: 'menu_book',
    colorKey: 'blue',
    ordem: 390,
  ),
  FinancialTipSeedDocument(
    docId: 'edu_lifestyle_inflation',
    titulo: 'Inflação de estilo de vida',
    descricao:
        'Ao ganhar mais, evite elevar gastos na mesma proporção. Direcione parte do aumento para poupança e metas.',
    categoriaSlug: 'educacao',
    iconKey: 'trending_up',
    colorKey: 'indigo',
    ordem: 400,
  ),
  FinancialTipSeedDocument(
    docId: 'edu_price_per_use',
    titulo: 'Custo por uso',
    descricao:
        'Divida o preço pelo número de vezes que vai usar. Compras caras com pouco uso costumam ser más negócios.',
    categoriaSlug: 'educacao',
    iconKey: 'search',
    colorKey: 'blueGrey',
    ordem: 410,
  ),
  FinancialTipSeedDocument(
    docId: 'edu_opportunity_cost',
    titulo: 'Custo de oportunidade',
    descricao:
        'Cada gasto hoje é dinheiro que não rende amanhã. Compare compras grandes com o valor futuro do mesmo montante.',
    categoriaSlug: 'educacao',
    iconKey: 'lightbulb',
    colorKey: 'primary',
    ordem: 420,
  ),
  // —— Comportamento (ampliado) ——
  FinancialTipSeedDocument(
    docId: 'beh_no_spend_day',
    titulo: 'Dia sem gastos',
    descricao:
        'Escolha um dia por semana sem compras extras. Pequeno hábito, grande impacto no fim do mês.',
    categoriaSlug: 'comportamento',
    iconKey: 'timer',
    colorKey: 'green',
    ordem: 430,
  ),
  FinancialTipSeedDocument(
    docId: 'beh_cash_envelope',
    titulo: 'Envelope digital',
    descricao:
        'Defina tetos por categoria (alimentação, lazer). Ao estourar, pare até o próximo ciclo — evita “só mais um”.',
    categoriaSlug: 'comportamento',
    iconKey: 'savings',
    colorKey: 'teal',
    ordem: 440,
  ),
  FinancialTipSeedDocument(
    docId: 'beh_trigger_spending',
    titulo: 'Gatilhos emocionais',
    descricao:
        'Estresse, tédio e redes sociais aumentam compras. Antes de abrir o app da loja, pause e registre o motivo.',
    categoriaSlug: 'comportamento',
    iconKey: 'warning',
    colorKey: 'deepOrange',
    ordem: 450,
  ),
  // —— Moradia (ampliado) ——
  FinancialTipSeedDocument(
    docId: 'home_energy_bill',
    titulo: 'Conta de luz',
    descricao:
        'Lâmpadas LED, desligar stand-by e ar-condicionado consciente reduzem a fatura sem mudar o padrão de vida.',
    categoriaSlug: 'moradia',
    iconKey: 'money_off',
    colorKey: 'green',
    ordem: 460,
    condicao: {
      'tipo': 'categoria_maior',
      'categoria': 'Moradia',
      'valor_min': 200,
    },
  ),
  FinancialTipSeedDocument(
    docId: 'home_rent_vs_buy',
    titulo: 'Aluguel x compra',
    descricao:
        'Compare custo total (entrada, juros, IPTU, manutenção) com aluguel + investimento da diferença. Não há resposta única.',
    categoriaSlug: 'moradia',
    iconKey: 'account_balance',
    colorKey: 'blueGrey',
    ordem: 470,
  ),
  // —— Transporte (ampliado) ——
  FinancialTipSeedDocument(
    docId: 'trans_car_total_cost',
    titulo: 'Custo total do carro',
    descricao:
        'Some combustível, seguro, IPVA, manutenção e depreciação. O custo real costuma ser maior que a parcela.',
    categoriaSlug: 'transporte',
    iconKey: 'directions_car',
    colorKey: 'orange',
    ordem: 480,
    condicao: {
      'tipo': 'concentracao_categoria',
      'categoria': 'Transporte',
      'pct_min': 22,
    },
  ),
  FinancialTipSeedDocument(
    docId: 'trans_public_when_possible',
    titulo: 'Alternativas ao carro',
    descricao:
        'Para trajetos fixos, transporte público ou carona compartilhada podem liberar centenas por mês.',
    categoriaSlug: 'transporte',
    iconKey: 'directions_car',
    colorKey: 'blue',
    ordem: 490,
  ),
  // —— Cartão (ampliado) ——
  FinancialTipSeedDocument(
    docId: 'card_minimum_payment_trap',
    titulo: 'Pagamento mínimo',
    descricao:
        'Pagar só o mínimo prolonga juros altíssimos. Priorize quitar a fatura integral ou renegociar a dívida.',
    categoriaSlug: 'cartao',
    iconKey: 'warning',
    colorKey: 'red',
    ordem: 500,
    condicao: {'tipo': 'gasto_maior_receita'},
  ),
  FinancialTipSeedDocument(
    docId: 'card_cashback_discipline',
    titulo: 'Cashback não é lucro',
    descricao:
        'Benefícios do cartão só valem se você pagar a fatura inteira. Juros anulam qualquer milha ou cashback.',
    categoriaSlug: 'cartao',
    iconKey: 'credit_card',
    colorKey: 'purple',
    ordem: 510,
  ),
  // —— Gastos / compras ——
  FinancialTipSeedDocument(
    docId: 'exp_compare_prices',
    titulo: 'Compare antes de comprar',
    descricao:
        'Pesquise em duas lojas ou use histórico de preço. Promoção falsa é comum — especialmente online.',
    categoriaSlug: 'gastos',
    iconKey: 'search',
    colorKey: 'blue',
    ordem: 520,
  ),
  FinancialTipSeedDocument(
    docId: 'exp_warranty_read',
    titulo: 'Garantia e devolução',
    descricao:
        'Guarde nota e prazo de troca. Compras grandes sem política clara de devolução aumentam risco.',
    categoriaSlug: 'gastos',
    iconKey: 'shield',
    colorKey: 'indigo',
    ordem: 530,
  ),
  FinancialTipSeedDocument(
    docId: 'exp_shopping_list',
    titulo: 'Lista no mercado',
    descricao:
        'Compre com lista e evite ir com fome. Supermercado sem plano é um dos maiores vazamentos do orçamento.',
    categoriaSlug: 'gastos',
    iconKey: 'menu_book',
    colorKey: 'green',
    ordem: 540,
    condicao: {
      'tipo': 'categoria_maior',
      'categoria': 'Alimentação',
      'valor_min': 300,
    },
  ),
  // —— Saúde (ampliado) ——
  FinancialTipSeedDocument(
    docId: 'health_preventive',
    titulo: 'Prevenção economiza',
    descricao:
        'Consultas e exames de rotina evitam emergências caras. Use a cobertura preventiva do plano quando houver.',
    categoriaSlug: 'saude',
    iconKey: 'shield',
    colorKey: 'teal',
    ordem: 550,
  ),
  FinancialTipSeedDocument(
    docId: 'health_gym_value',
    titulo: 'Academia: use ou cancele',
    descricao:
        'Mensalidade esquecida é dinheiro jogado fora. Se foi menos de 8 vezes no mês, reavalie plano ou modalidade.',
    categoriaSlug: 'saude',
    iconKey: 'subscriptions',
    colorKey: 'orange',
    ordem: 560,
  ),
  // —— Lazer (ampliado) ——
  FinancialTipSeedDocument(
    docId: 'leisure_free_options',
    titulo: 'Lazer gratuito',
    descricao:
        'Parques, eventos públicos e encontros em casa mantêm qualidade de vida sem estourar o teto de lazer.',
    categoriaSlug: 'lazer',
    iconKey: 'lightbulb',
    colorKey: 'green',
    ordem: 570,
  ),
  FinancialTipSeedDocument(
    docId: 'leisure_concentration',
    titulo: 'Lazer pesando no mês?',
    descricao:
        'Quando lazer concentra grande fatia das despesas, combine um teto e alterne meses mais calmos.',
    categoriaSlug: 'lazer',
    iconKey: 'bar_chart',
    colorKey: 'purple',
    ordem: 580,
    condicao: {
      'tipo': 'concentracao_categoria',
      'categoria': 'Lazer',
      'pct_min': 25,
    },
  ),
  // —— Investimento (ampliado) ——
  FinancialTipSeedDocument(
    docId: 'inv_automatic_debit',
    titulo: 'Aporte automático',
    descricao:
        'Programar transferência no dia do salário tira a decisão do caminho. Disciplina automática vence força de vontade.',
    categoriaSlug: 'investimento',
    iconKey: 'savings',
    colorKey: 'green',
    ordem: 590,
  ),
  FinancialTipSeedDocument(
    docId: 'inv_retirement_early',
    titulo: 'Aposentadoria cedo demais para pensar?',
    descricao:
        'Quanto antes começar, menos precisa aportar por mês. Mesmo valores pequenos fazem diferença em 20–30 anos.',
    categoriaSlug: 'investimento',
    iconKey: 'trending_up',
    colorKey: 'indigo',
    ordem: 600,
  ),
  FinancialTipSeedDocument(
    docId: 'inv_emergency_liquidity',
    titulo: 'Liquidez da reserva',
    descricao:
        'Reserva de emergência precisa estar disponível em 1–2 dias. Evite travar esse dinheiro em prazos longos.',
    categoriaSlug: 'investimento',
    iconKey: 'account_balance',
    colorKey: 'teal',
    ordem: 610,
  ),
  // —— Dívidas ——
  FinancialTipSeedDocument(
    docId: 'debt_renegotiate',
    titulo: 'Renegocie juros altos',
    descricao:
        'Bancos e credores costumam aceitar acordo melhor do que inadimplência total. Peça proposta por escrito.',
    categoriaSlug: 'dividas',
    iconKey: 'warning',
    colorKey: 'red',
    ordem: 620,
    condicao: {'tipo': 'gasto_maior_receita'},
  ),
  FinancialTipSeedDocument(
    docId: 'debt_no_new_credit',
    titulo: 'Não rolar dívida',
    descricao:
        'Evite pegar empréstimo para pagar cartão sem plano. Corte gasto e ataque a taxa mais alta primeiro.',
    categoriaSlug: 'dividas',
    iconKey: 'money_off',
    colorKey: 'deepOrange',
    ordem: 630,
  ),
  // —— Trabalho / renda ——
  FinancialTipSeedDocument(
    docId: 'work_side_income_tax',
    titulo: 'Renda extra: guarde imposto',
    descricao:
        'Freelas e bicos podem gerar obrigação fiscal. Separe percentual desde o recebimento para não ser pego de surpresa.',
    categoriaSlug: 'trabalho',
    iconKey: 'percent',
    colorKey: 'orange',
    ordem: 640,
  ),
  FinancialTipSeedDocument(
    docId: 'work_skill_invest',
    titulo: 'Invista em habilidade',
    descricao:
        'Curso ou certificação que aumenta renda pode ser melhor “investimento” que ativo especulativo no curto prazo.',
    categoriaSlug: 'trabalho',
    iconKey: 'trending_up',
    colorKey: 'blue',
    ordem: 650,
  ),
  // —— Família / filhos ——
  FinancialTipSeedDocument(
    docId: 'family_kids_transparency',
    titulo: 'Finanças em família',
    descricao:
        'Envolver filhos em metas simples (mesada, poupança) educa cedo e reduz pedidos por impulso.',
    categoriaSlug: 'familia',
    iconKey: 'lightbulb',
    colorKey: 'primary',
    ordem: 660,
  ),
  FinancialTipSeedDocument(
    docId: 'family_shared_goals',
    titulo: 'Meta conjunta',
    descricao:
        'Viagem ou reforma em casal/família funciona melhor com valor mensal combinado e acompanhamento no app.',
    categoriaSlug: 'familia',
    iconKey: 'savings',
    colorKey: 'green',
    ordem: 670,
  ),
  // —— Pets ——
  FinancialTipSeedDocument(
    docId: 'pet_monthly_budget',
    titulo: 'Orçamento pet',
    descricao:
        'Ração, vet e banho são recorrentes. Ter teto mensal evita surpresas e compras por impulso no pet shop.',
    categoriaSlug: 'pets',
    iconKey: 'savings',
    colorKey: 'teal',
    ordem: 680,
  ),
  // —— Segurança (ampliado) ——
  FinancialTipSeedDocument(
    docId: 'sec_phishing_links',
    titulo: 'Links suspeitos',
    descricao:
        'Não clique em SMS ou e-mail pedindo senha ou Pix. Acesse o app digitando o endereço ou use atalho salvo.',
    categoriaSlug: 'seguranca',
    iconKey: 'shield',
    colorKey: 'red',
    ordem: 690,
  ),
  FinancialTipSeedDocument(
    docId: 'sec_card_virtual',
    titulo: 'Cartão virtual',
    descricao:
        'Para compras online, use cartão virtual com limite. Se vazar, cancela só aquele número.',
    categoriaSlug: 'seguranca',
    iconKey: 'credit_card',
    colorKey: 'indigo',
    ordem: 700,
  ),
  // —— Metas (ampliado) ——
  FinancialTipSeedDocument(
    docId: 'goal_visualize_progress',
    titulo: 'Veja o progresso',
    descricao:
        'Metas com percentual visível motivam. Atualize aportes no módulo Metas sempre que guardar algo.',
    categoriaSlug: 'metas',
    iconKey: 'bar_chart',
    colorKey: 'green',
    ordem: 710,
  ),
  FinancialTipSeedDocument(
    docId: 'goal_emergency_first',
    titulo: 'Meta antes de luxo',
    descricao:
        'Priorize reserva de emergência antes de metas de consumo (celular, viagem). Ordem certa evita voltar ao cartão.',
    categoriaSlug: 'metas',
    iconKey: 'shield',
    colorKey: 'teal',
    ordem: 720,
  ),
  // —— Controle (ampliado) ——
  FinancialTipSeedDocument(
    docId: 'ctrl_reconcile_bank',
    titulo: 'Concilie com o banco',
    descricao:
        'Compare lançamentos do app com extrato semanal. Divergências aparecem cedo — assinaturas e taxas escondidas.',
    categoriaSlug: 'controle',
    iconKey: 'search',
    colorKey: 'blue',
    ordem: 730,
  ),
  FinancialTipSeedDocument(
    docId: 'ctrl_tag_transfers',
    titulo: 'Transferências entre contas',
    descricao:
        'Movimentação entre suas contas não é despesa. Marque corretamente para não distorcer gráficos e dicas.',
    categoriaSlug: 'controle',
    iconKey: 'bar_chart',
    colorKey: 'indigo',
    ordem: 740,
  ),
];

/// Entradas para o seletor local (app offline / fallback).
List<FinanceTipBankEntry> buildFinanceTipBankFromSeed() =>
    kFinancialTipsFirestoreSeedBank.map((s) => s.toBankEntry()).toList();
