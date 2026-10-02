import 'package:flutter/material.dart';

import 'commitment_presets.dart';

/// Símbolo que o usuário escolhe para o compromisso: um emoji ou um ícone
/// moderno. Fica em um campo só, `commitmentSymbol`, no reminder e no espelho
/// `scales/agenda_*` — `emoji:🎂` ou `icon:cake`. Sem o campo, o ícone continua
/// sendo deduzido do título ([resolveCommitmentVisual]).
///
/// Ícones saem sempre deste mapa constante: `IconData(codePoint)` montado em
/// tempo de execução quebra o tree-shake de ícones no release (iOS e web).
const String kCommitmentSymbolField = 'commitmentSymbol';

/// Emoji do seletor com palavras-chave em pt-BR para a busca.
class CommitmentEmoji {
  const CommitmentEmoji(this.emoji, this.palavras);
  final String emoji;
  final String palavras;
}

class CommitmentEmojiGroup {
  const CommitmentEmojiGroup(this.titulo, this.icone, this.itens);
  final String titulo;
  final IconData icone;
  final List<CommitmentEmoji> itens;

  List<String> get emojis => [for (final e in itens) e.emoji];
}

const List<CommitmentEmojiGroup> kCommitmentEmojiGroups = [
  CommitmentEmojiGroup('Comemorações', Icons.celebration_rounded, [
    CommitmentEmoji('🎂', 'aniversário bolo parabéns niver'),
    CommitmentEmoji('🎉', 'festa comemoração aniversário parabéns'),
    CommitmentEmoji('🥳', 'festa aniversário comemorar'),
    CommitmentEmoji('🎁', 'presente aniversário amigo secreto'),
    CommitmentEmoji('🎈', 'balão festa aniversário'),
    CommitmentEmoji('🍰', 'bolo doce aniversário'),
    CommitmentEmoji('🧁', 'cupcake doce festa'),
    CommitmentEmoji('🎊', 'confete festa comemoração'),
    CommitmentEmoji('🍾', 'champanhe brinde comemoração'),
    CommitmentEmoji('🥂', 'brinde taça comemoração'),
    CommitmentEmoji('💍', 'casamento noivado aliança anel'),
    CommitmentEmoji('💒', 'casamento igreja cerimônia'),
    CommitmentEmoji('👰', 'noiva casamento'),
    CommitmentEmoji('🤵', 'noivo casamento'),
    CommitmentEmoji('💐', 'flores buquê casamento homenagem'),
    CommitmentEmoji('👶', 'bebê nascimento chá de bebê'),
    CommitmentEmoji('🍼', 'bebê mamadeira chá de bebê'),
    CommitmentEmoji('🤰', 'gestante gravidez pré-natal'),
    CommitmentEmoji('🎓', 'formatura graduação colação'),
    CommitmentEmoji('🏆', 'troféu conquista prêmio campeonato'),
    CommitmentEmoji('🥇', 'medalha primeiro lugar prêmio'),
    CommitmentEmoji('🎖️', 'medalha homenagem condecoração'),
    CommitmentEmoji('🕯️', 'vela memória falecimento missa luto'),
    CommitmentEmoji('💝', 'presente amor dia dos namorados'),
  ]),
  CommitmentEmojiGroup('Família e pessoas', Icons.family_restroom_rounded, [
    CommitmentEmoji('👨‍👩‍👧', 'família pais filhos'),
    CommitmentEmoji('👪', 'família'),
    CommitmentEmoji('👨‍👩‍👧‍👦', 'família filhos'),
    CommitmentEmoji('👫', 'casal amigos'),
    CommitmentEmoji('💑', 'casal namoro amor'),
    CommitmentEmoji('❤️', 'amor coração namoro'),
    CommitmentEmoji('💕', 'amor carinho'),
    CommitmentEmoji('🌹', 'rosa dia das mães amor'),
    CommitmentEmoji('👵', 'avó vovó idosa'),
    CommitmentEmoji('👴', 'avô vovô idoso'),
    CommitmentEmoji('👧', 'filha menina criança'),
    CommitmentEmoji('👦', 'filho menino criança'),
    CommitmentEmoji('🧒', 'criança escola'),
    CommitmentEmoji('🤱', 'mãe amamentação bebê'),
    CommitmentEmoji('👔', 'dia dos pais pai gravata'),
    CommitmentEmoji('🤗', 'abraço visita amigos'),
    CommitmentEmoji('🫂', 'abraço apoio visita'),
    CommitmentEmoji('👥', 'pessoas grupo reunião'),
  ]),
  CommitmentEmojiGroup('Saúde', Icons.health_and_safety_rounded, [
    CommitmentEmoji('🏥', 'hospital consulta exame'),
    CommitmentEmoji('🩺', 'médico consulta clínico'),
    CommitmentEmoji('🦷', 'dentista dente odontologia'),
    CommitmentEmoji('💉', 'vacina injeção exame de sangue'),
    CommitmentEmoji('💊', 'remédio medicamento farmácia'),
    CommitmentEmoji('🩹', 'curativo ferimento'),
    CommitmentEmoji('🩻', 'raio x exame imagem'),
    CommitmentEmoji('🧪', 'exame laboratório'),
    CommitmentEmoji('🧠', 'psicólogo psiquiatra terapia mente'),
    CommitmentEmoji('👁️', 'oftalmologista olho óculos'),
    CommitmentEmoji('👓', 'óculos ótica oftalmologista'),
    CommitmentEmoji('🫀', 'cardiologista coração'),
    CommitmentEmoji('🦴', 'ortopedista osso fisioterapia'),
    CommitmentEmoji('🧘', 'yoga meditação relaxar'),
    CommitmentEmoji('💆', 'massagem estética spa'),
    CommitmentEmoji('💇', 'cabeleireiro corte de cabelo salão'),
    CommitmentEmoji('💅', 'manicure unha salão'),
    CommitmentEmoji('🥗', 'nutricionista dieta salada'),
    CommitmentEmoji('😴', 'sono descanso dormir'),
    CommitmentEmoji('🚑', 'ambulância emergência'),
  ]),
  CommitmentEmojiGroup('Esporte e academia', Icons.fitness_center_rounded, [
    CommitmentEmoji('🏋️', 'academia musculação treino'),
    CommitmentEmoji('💪', 'treino força academia'),
    CommitmentEmoji('🏃', 'corrida caminhada'),
    CommitmentEmoji('🚴', 'bicicleta pedal ciclismo'),
    CommitmentEmoji('🏊', 'natação piscina'),
    CommitmentEmoji('⚽', 'futebol jogo pelada'),
    CommitmentEmoji('🏀', 'basquete'),
    CommitmentEmoji('🏐', 'vôlei'),
    CommitmentEmoji('🎾', 'tênis'),
    CommitmentEmoji('🥊', 'luta boxe'),
    CommitmentEmoji('🥋', 'jiu-jitsu judô karatê luta'),
    CommitmentEmoji('🤸', 'ginástica pilates alongamento'),
    CommitmentEmoji('⛳', 'golfe'),
    CommitmentEmoji('🏄', 'surf praia'),
    CommitmentEmoji('🛹', 'skate'),
    CommitmentEmoji('🏅', 'medalha competição prova'),
  ]),
  CommitmentEmojiGroup('Trabalho', Icons.work_rounded, [
    CommitmentEmoji('💼', 'trabalho reunião escritório'),
    CommitmentEmoji('🤝', 'reunião acordo negócio cliente'),
    CommitmentEmoji('📊', 'relatório apresentação planilha'),
    CommitmentEmoji('📈', 'meta vendas resultado'),
    CommitmentEmoji('💻', 'computador home office reunião online'),
    CommitmentEmoji('🖥️', 'computador sistema'),
    CommitmentEmoji('📞', 'ligação telefone chamada'),
    CommitmentEmoji('📱', 'celular ligação whatsapp'),
    CommitmentEmoji('📧', 'email e-mail mensagem'),
    CommitmentEmoji('📝', 'anotação tarefa documento'),
    CommitmentEmoji('📄', 'documento papel contrato'),
    CommitmentEmoji('📋', 'lista prancheta checklist'),
    CommitmentEmoji('🗂️', 'arquivo pasta processo'),
    CommitmentEmoji('⚖️', 'audiência justiça advogado processo'),
    CommitmentEmoji('🏛️', 'fórum tribunal órgão público'),
    CommitmentEmoji('👨‍⚖️', 'juiz audiência'),
    CommitmentEmoji('🚓', 'polícia viatura plantão'),
    CommitmentEmoji('👮', 'policial plantão serviço'),
    CommitmentEmoji('🛡️', 'segurança proteção plantão'),
    CommitmentEmoji('🚒', 'bombeiro plantão'),
    CommitmentEmoji('👷', 'obra construção engenheiro'),
    CommitmentEmoji('🏗️', 'obra construção'),
    CommitmentEmoji('🧑‍💼', 'executivo entrevista emprego'),
    CommitmentEmoji('🎤', 'palestra apresentação evento'),
  ]),
  CommitmentEmojiGroup('Estudo', Icons.school_rounded, [
    CommitmentEmoji('📚', 'estudo livros aula'),
    CommitmentEmoji('📖', 'leitura livro estudo'),
    CommitmentEmoji('✏️', 'lápis prova estudo'),
    CommitmentEmoji('🖊️', 'caneta assinatura'),
    CommitmentEmoji('🏫', 'escola colégio reunião de pais'),
    CommitmentEmoji('🎒', 'mochila escola volta às aulas'),
    CommitmentEmoji('🧮', 'matemática cálculo'),
    CommitmentEmoji('🔬', 'ciência laboratório pesquisa'),
    CommitmentEmoji('🌐', 'curso online idioma'),
    CommitmentEmoji('🗣️', 'idioma inglês conversa'),
    CommitmentEmoji('📐', 'projeto desenho régua'),
    CommitmentEmoji('🧑‍🏫', 'professor aula'),
    CommitmentEmoji('🧑‍🎓', 'estudante faculdade'),
    CommitmentEmoji('📜', 'certificado diploma'),
  ]),
  CommitmentEmojiGroup('Dinheiro e contas', Icons.payments_rounded, [
    CommitmentEmoji('💰', 'dinheiro pagamento salário'),
    CommitmentEmoji('💵', 'dinheiro dólar pagamento'),
    CommitmentEmoji('💸', 'gasto despesa pagar'),
    CommitmentEmoji('💳', 'cartão fatura crédito'),
    CommitmentEmoji('🏦', 'banco agência'),
    CommitmentEmoji('🧾', 'boleto conta recibo nota'),
    CommitmentEmoji('📉', 'queda prejuízo'),
    CommitmentEmoji('🪙', 'moeda investimento'),
    CommitmentEmoji('🐷', 'cofrinho poupança economia'),
    CommitmentEmoji('💲', 'preço valor cobrança'),
    CommitmentEmoji('🧮', 'imposto contador cálculo'),
    CommitmentEmoji('📅', 'vencimento data prazo'),
  ]),
  CommitmentEmojiGroup('Casa', Icons.home_rounded, [
    CommitmentEmoji('🏠', 'casa lar'),
    CommitmentEmoji('🏡', 'casa sítio'),
    CommitmentEmoji('🔑', 'chave aluguel mudança'),
    CommitmentEmoji('🧹', 'faxina limpeza'),
    CommitmentEmoji('🧺', 'roupa lavanderia'),
    CommitmentEmoji('🧽', 'limpeza louça'),
    CommitmentEmoji('🛠️', 'conserto manutenção reparo'),
    CommitmentEmoji('🔧', 'manutenção conserto ferramenta'),
    CommitmentEmoji('🔨', 'reforma conserto'),
    CommitmentEmoji('🪴', 'planta jardim'),
    CommitmentEmoji('🚿', 'chuveiro banho encanador'),
    CommitmentEmoji('💡', 'luz energia conta de luz ideia'),
    CommitmentEmoji('🚰', 'água conta de água'),
    CommitmentEmoji('📦', 'entrega encomenda mudança'),
    CommitmentEmoji('🛋️', 'móveis sofá'),
    CommitmentEmoji('🛏️', 'cama quarto'),
  ]),
  CommitmentEmojiGroup('Comida e bebida', Icons.restaurant_rounded, [
    CommitmentEmoji('🍽️', 'almoço jantar refeição'),
    CommitmentEmoji('☕', 'café manhã'),
    CommitmentEmoji('🍕', 'pizza'),
    CommitmentEmoji('🍔', 'lanche hambúrguer'),
    CommitmentEmoji('🍖', 'churrasco carne'),
    CommitmentEmoji('🥩', 'churrasco carne açougue'),
    CommitmentEmoji('🍝', 'massa macarrão jantar'),
    CommitmentEmoji('🍣', 'sushi japonês'),
    CommitmentEmoji('🍺', 'cerveja bar happy hour'),
    CommitmentEmoji('🍷', 'vinho jantar'),
    CommitmentEmoji('🥤', 'refrigerante bebida'),
    CommitmentEmoji('🍞', 'pão padaria'),
    CommitmentEmoji('🍳', 'cozinhar café da manhã'),
    CommitmentEmoji('🥘', 'comida panela almoço'),
  ]),
  CommitmentEmojiGroup('Compras', Icons.shopping_bag_rounded, [
    CommitmentEmoji('🛒', 'mercado compras supermercado'),
    CommitmentEmoji('🛍️', 'compras shopping loja'),
    CommitmentEmoji('🏪', 'loja conveniência'),
    CommitmentEmoji('👕', 'roupa camisa'),
    CommitmentEmoji('👗', 'vestido roupa'),
    CommitmentEmoji('👟', 'tênis calçado'),
    CommitmentEmoji('💄', 'maquiagem beleza'),
    CommitmentEmoji('🧴', 'cosmético farmácia'),
    CommitmentEmoji('🏷️', 'promoção etiqueta preço'),
  ]),
  CommitmentEmojiGroup('Transporte', Icons.directions_car_rounded, [
    CommitmentEmoji('🚗', 'carro viagem'),
    CommitmentEmoji('🚙', 'carro suv'),
    CommitmentEmoji('🏍️', 'moto'),
    CommitmentEmoji('🚕', 'táxi uber corrida'),
    CommitmentEmoji('🚌', 'ônibus'),
    CommitmentEmoji('🚇', 'metrô'),
    CommitmentEmoji('🚆', 'trem'),
    CommitmentEmoji('✈️', 'avião voo viagem'),
    CommitmentEmoji('🛫', 'embarque voo aeroporto'),
    CommitmentEmoji('🚢', 'navio cruzeiro'),
    CommitmentEmoji('⛽', 'combustível posto gasolina'),
    CommitmentEmoji('🅿️', 'estacionamento'),
    CommitmentEmoji('🔧', 'oficina revisão mecânico'),
    CommitmentEmoji('🚦', 'trânsito detran'),
    CommitmentEmoji('🪪', 'documento cnh identidade'),
  ]),
  CommitmentEmojiGroup('Lazer e viagem', Icons.beach_access_rounded, [
    CommitmentEmoji('🏖️', 'praia férias'),
    CommitmentEmoji('🏝️', 'ilha viagem férias'),
    CommitmentEmoji('⛺', 'acampamento camping'),
    CommitmentEmoji('🏔️', 'montanha viagem'),
    CommitmentEmoji('🧳', 'mala viagem'),
    CommitmentEmoji('🗺️', 'mapa passeio roteiro'),
    CommitmentEmoji('🎬', 'cinema filme'),
    CommitmentEmoji('🍿', 'cinema pipoca filme'),
    CommitmentEmoji('🎭', 'teatro espetáculo'),
    CommitmentEmoji('🎵', 'música show'),
    CommitmentEmoji('🎸', 'violão guitarra show'),
    CommitmentEmoji('🎤', 'karaokê show cantar'),
    CommitmentEmoji('🎮', 'videogame jogo'),
    CommitmentEmoji('🎲', 'jogo tabuleiro'),
    CommitmentEmoji('🎣', 'pescaria pesca'),
    CommitmentEmoji('🎡', 'parque diversão'),
    CommitmentEmoji('📷', 'fotos passeio'),
  ]),
  CommitmentEmojiGroup('Religião e igreja', Icons.church_rounded, [
    CommitmentEmoji('⛪', 'igreja missa culto batizado'),
    CommitmentEmoji('🙏', 'oração reza fé'),
    CommitmentEmoji('✝️', 'cruz fé cristão'),
    CommitmentEmoji('📿', 'terço rosário'),
    CommitmentEmoji('🕊️', 'pomba paz espírito'),
    CommitmentEmoji('📖', 'bíblia leitura estudo bíblico'),
    CommitmentEmoji('🛐', 'culto adoração'),
    CommitmentEmoji('😇', 'anjo fé'),
  ]),
  CommitmentEmojiGroup('Pets', Icons.pets_rounded, [
    CommitmentEmoji('🐶', 'cachorro cão pet'),
    CommitmentEmoji('🐱', 'gato pet'),
    CommitmentEmoji('🐾', 'pet patas veterinário'),
    CommitmentEmoji('🦮', 'passeio cachorro'),
    CommitmentEmoji('🐦', 'pássaro ave'),
    CommitmentEmoji('🐠', 'peixe aquário'),
    CommitmentEmoji('🐴', 'cavalo'),
    CommitmentEmoji('🩺', 'veterinário vacina pet'),
  ]),
  CommitmentEmojiGroup('Tecnologia', Icons.devices_rounded, [
    CommitmentEmoji('💻', 'notebook computador'),
    CommitmentEmoji('📱', 'celular aplicativo'),
    CommitmentEmoji('⌚', 'relógio smartwatch'),
    CommitmentEmoji('🖨️', 'impressora imprimir'),
    CommitmentEmoji('📡', 'internet antena'),
    CommitmentEmoji('🔋', 'bateria carregar'),
    CommitmentEmoji('🔌', 'tomada carregador'),
    CommitmentEmoji('💾', 'backup salvar'),
    CommitmentEmoji('🎧', 'fone áudio podcast'),
    CommitmentEmoji('📺', 'tv televisão'),
    CommitmentEmoji('🤖', 'robô automação ia'),
  ]),
  CommitmentEmojiGroup('Natureza e clima', Icons.park_rounded, [
    CommitmentEmoji('🌱', 'planta broto jardim'),
    CommitmentEmoji('🌳', 'árvore parque'),
    CommitmentEmoji('🌻', 'girassol flor'),
    CommitmentEmoji('🌸', 'flor primavera'),
    CommitmentEmoji('☀️', 'sol calor verão'),
    CommitmentEmoji('🌧️', 'chuva'),
    CommitmentEmoji('⛈️', 'tempestade'),
    CommitmentEmoji('❄️', 'frio inverno'),
    CommitmentEmoji('🌙', 'lua noite'),
    CommitmentEmoji('🌈', 'arco-íris'),
    CommitmentEmoji('🌊', 'mar onda praia'),
    CommitmentEmoji('🔥', 'fogo urgente'),
  ]),
  CommitmentEmojiGroup('Símbolos e alertas', Icons.priority_high_rounded, [
    CommitmentEmoji('⭐', 'estrela importante favorito'),
    CommitmentEmoji('🌟', 'brilho destaque'),
    CommitmentEmoji('❗', 'importante atenção'),
    CommitmentEmoji('‼️', 'urgente importante'),
    CommitmentEmoji('⚠️', 'atenção aviso cuidado'),
    CommitmentEmoji('✅', 'feito concluído ok'),
    CommitmentEmoji('☑️', 'tarefa checklist'),
    CommitmentEmoji('❌', 'cancelado não'),
    CommitmentEmoji('⏰', 'despertador alarme hora'),
    CommitmentEmoji('⏳', 'prazo tempo'),
    CommitmentEmoji('📌', 'lembrete fixar'),
    CommitmentEmoji('📍', 'local endereço'),
    CommitmentEmoji('🔔', 'aviso lembrete notificação'),
    CommitmentEmoji('📣', 'anúncio aviso'),
    CommitmentEmoji('💬', 'mensagem conversa'),
    CommitmentEmoji('❤️', 'amor favorito'),
    CommitmentEmoji('💯', 'cem perfeito'),
    CommitmentEmoji('🔴', 'vermelho urgente'),
    CommitmentEmoji('🟢', 'verde ok'),
    CommitmentEmoji('🔵', 'azul'),
    CommitmentEmoji('🟡', 'amarelo atenção'),
    CommitmentEmoji('🟣', 'roxo'),
    CommitmentEmoji('✂️', 'corte'),
    CommitmentEmoji('🔒', 'cadeado senha segurança'),
  ]),
  CommitmentEmojiGroup('Bandeiras e datas', Icons.flag_rounded, [
    CommitmentEmoji('🇧🇷', 'brasil bandeira feriado independência'),
    CommitmentEmoji('🎄', 'natal árvore'),
    CommitmentEmoji('🎅', 'papai noel natal'),
    CommitmentEmoji('🎆', 'ano novo réveillon fogos'),
    CommitmentEmoji('🎇', 'fogos réveillon'),
    CommitmentEmoji('🐣', 'páscoa'),
    CommitmentEmoji('🐰', 'páscoa coelho'),
    CommitmentEmoji('🎃', 'halloween dia das bruxas'),
    CommitmentEmoji('🎭', 'carnaval'),
    CommitmentEmoji('🪅', 'festa junina'),
    CommitmentEmoji('🌽', 'festa junina milho'),
    CommitmentEmoji('🔥', 'fogueira são joão'),
    CommitmentEmoji('💘', 'dia dos namorados'),
    CommitmentEmoji('👩‍🏫', 'dia do professor'),
    CommitmentEmoji('🧒', 'dia das crianças'),
    CommitmentEmoji('🏳️', 'bandeira branca paz'),
    CommitmentEmoji('🏁', 'chegada fim'),
  ]),
];

/// Ícones modernos (Material arredondados) por chave estável.
/// NUNCA renomear/remover chaves: o valor gravado é `icon:<chave>`.
const Map<String, IconData> kCommitmentIcons = {
  'cake': Icons.cake_rounded,
  'celebration': Icons.celebration_rounded,
  'favorite': Icons.favorite_rounded,
  'diamond': Icons.diamond_rounded,
  'redeem': Icons.redeem_rounded,
  'child': Icons.child_friendly_rounded,
  'school': Icons.school_rounded,
  'star': Icons.star_rounded,
  'family': Icons.family_restroom_rounded,
  'home': Icons.home_rounded,
  'pets': Icons.pets_rounded,
  'restaurant': Icons.restaurant_rounded,
  'shopping': Icons.shopping_cart_rounded,
  'medical': Icons.medical_services_rounded,
  'vaccine': Icons.vaccines_rounded,
  'psychology': Icons.psychology_rounded,
  'fitness': Icons.fitness_center_rounded,
  'work': Icons.work_rounded,
  'groups': Icons.groups_rounded,
  'handshake': Icons.handshake_rounded,
  'gavel': Icons.gavel_rounded,
  'shield': Icons.shield_rounded,
  'payments': Icons.payments_rounded,
  'bank': Icons.account_balance_rounded,
  'receipt': Icons.receipt_long_rounded,
  'flight': Icons.flight_takeoff_rounded,
  'beach': Icons.beach_access_rounded,
  'car': Icons.directions_car_rounded,
  'build': Icons.build_rounded,
  'church': Icons.church_rounded,
  'music': Icons.music_note_rounded,
  'sports': Icons.sports_soccer_rounded,
  'event': Icons.event_available_rounded,
  'alarm': Icons.alarm_rounded,
  'bell': Icons.notifications_active_rounded,
  'flag': Icons.flag_rounded,
  'bolt': Icons.bolt_rounded,
  'lightbulb': Icons.lightbulb_rounded,
  // Novos (02/10/2026)
  'local_hospital': Icons.local_hospital_rounded,
  'healing': Icons.healing_rounded,
  'monitor_heart': Icons.monitor_heart_rounded,
  'medication': Icons.medication_rounded,
  'spa': Icons.spa_rounded,
  'self_improvement': Icons.self_improvement_rounded,
  'directions_run': Icons.directions_run_rounded,
  'pool': Icons.pool_rounded,
  'directions_bike': Icons.directions_bike_rounded,
  'sports_basketball': Icons.sports_basketball_rounded,
  'sports_tennis': Icons.sports_tennis_rounded,
  'sports_martial_arts': Icons.sports_martial_arts_rounded,
  'business_center': Icons.business_center_rounded,
  'meeting_room': Icons.meeting_room_rounded,
  'call': Icons.call_rounded,
  'videocam': Icons.videocam_rounded,
  'mail': Icons.mail_rounded,
  'description': Icons.description_rounded,
  'assignment': Icons.assignment_rounded,
  'balance': Icons.balance_rounded,
  'local_police': Icons.local_police_rounded,
  'engineering': Icons.engineering_rounded,
  'construction': Icons.construction_rounded,
  'menu_book': Icons.menu_book_rounded,
  'edit_note': Icons.edit_note_rounded,
  'science': Icons.science_rounded,
  'language': Icons.language_rounded,
  'workspace_premium': Icons.workspace_premium_rounded,
  'savings': Icons.savings_rounded,
  'credit_card': Icons.credit_card_rounded,
  'attach_money': Icons.attach_money_rounded,
  'trending_up': Icons.trending_up_rounded,
  'request_quote': Icons.request_quote_rounded,
  'cleaning': Icons.cleaning_services_rounded,
  'local_laundry': Icons.local_laundry_service_rounded,
  'handyman': Icons.handyman_rounded,
  'yard': Icons.yard_rounded,
  'key': Icons.key_rounded,
  'local_shipping': Icons.local_shipping_rounded,
  'chair': Icons.chair_rounded,
  'local_cafe': Icons.local_cafe_rounded,
  'local_pizza': Icons.local_pizza_rounded,
  'outdoor_grill': Icons.outdoor_grill_rounded,
  'local_bar': Icons.local_bar_rounded,
  'bakery': Icons.bakery_dining_rounded,
  'shopping_bag': Icons.shopping_bag_rounded,
  'store': Icons.store_rounded,
  'checkroom': Icons.checkroom_rounded,
  'local_offer': Icons.local_offer_rounded,
  'two_wheeler': Icons.two_wheeler_rounded,
  'local_taxi': Icons.local_taxi_rounded,
  'directions_bus': Icons.directions_bus_rounded,
  'train': Icons.train_rounded,
  'local_gas_station': Icons.local_gas_station_rounded,
  'local_parking': Icons.local_parking_rounded,
  'luggage': Icons.luggage_rounded,
  'hiking': Icons.hiking_rounded,
  'movie': Icons.movie_rounded,
  'theater': Icons.theater_comedy_rounded,
  'sports_esports': Icons.sports_esports_rounded,
  'camera': Icons.photo_camera_rounded,
  'park': Icons.park_rounded,
  'volunteer': Icons.volunteer_activism_rounded,
  'auto_stories': Icons.auto_stories_rounded,
  'laptop': Icons.laptop_mac_rounded,
  'smartphone': Icons.smartphone_rounded,
  'watch': Icons.watch_rounded,
  'print': Icons.print_rounded,
  'wifi': Icons.wifi_rounded,
  'wb_sunny': Icons.wb_sunny_rounded,
  'water_drop': Icons.water_drop_rounded,
  'ac_unit': Icons.ac_unit_rounded,
  'nightlight': Icons.nightlight_rounded,
  'priority_high': Icons.priority_high_rounded,
  'warning': Icons.warning_amber_rounded,
  'check_circle': Icons.check_circle_rounded,
  'push_pin': Icons.push_pin_rounded,
  'place': Icons.place_rounded,
  'hourglass': Icons.hourglass_bottom_rounded,
  'campaign': Icons.campaign_rounded,
  'chat': Icons.chat_bubble_rounded,
  'lock': Icons.lock_rounded,
  'person': Icons.person_rounded,
  'elderly': Icons.elderly_rounded,
  'pregnant': Icons.pregnant_woman_rounded,
  'baby': Icons.baby_changing_station_rounded,
  'emoji_events': Icons.emoji_events_rounded,
  'military_tech': Icons.military_tech_rounded,
  'card_giftcard': Icons.card_giftcard_rounded,
  'local_florist': Icons.local_florist_rounded,
};

/// Ícone do seletor com palavras-chave em pt-BR.
class CommitmentIconEntry {
  const CommitmentIconEntry(this.key, this.palavras);
  final String key;
  final String palavras;
}

class CommitmentIconGroup {
  const CommitmentIconGroup(this.titulo, this.itens);
  final String titulo;
  final List<CommitmentIconEntry> itens;
}

/// Grupos da aba «Ícones modernos» (todas as chaves de [kCommitmentIcons]).
const List<CommitmentIconGroup> kCommitmentIconGroups = [
  CommitmentIconGroup('Comemorações', [
    CommitmentIconEntry('cake', 'aniversário bolo'),
    CommitmentIconEntry('celebration', 'festa comemoração'),
    CommitmentIconEntry('redeem', 'presente'),
    CommitmentIconEntry('card_giftcard', 'presente vale'),
    CommitmentIconEntry('diamond', 'casamento noivado'),
    CommitmentIconEntry('favorite', 'amor coração'),
    CommitmentIconEntry('local_florist', 'flores homenagem'),
    CommitmentIconEntry('emoji_events', 'troféu conquista'),
    CommitmentIconEntry('military_tech', 'medalha homenagem'),
    CommitmentIconEntry('workspace_premium', 'formatura certificado'),
    CommitmentIconEntry('star', 'estrela importante'),
  ]),
  CommitmentIconGroup('Família e pessoas', [
    CommitmentIconEntry('family', 'família'),
    CommitmentIconEntry('child', 'bebê criança'),
    CommitmentIconEntry('baby', 'bebê fralda'),
    CommitmentIconEntry('pregnant', 'gestante pré-natal'),
    CommitmentIconEntry('elderly', 'idoso avós'),
    CommitmentIconEntry('person', 'pessoa'),
    CommitmentIconEntry('groups', 'grupo reunião'),
    CommitmentIconEntry('volunteer', 'voluntário ajuda doação'),
  ]),
  CommitmentIconGroup('Saúde e esporte', [
    CommitmentIconEntry('medical', 'médico consulta'),
    CommitmentIconEntry('local_hospital', 'hospital'),
    CommitmentIconEntry('healing', 'curativo tratamento'),
    CommitmentIconEntry('monitor_heart', 'coração exame cardiologista'),
    CommitmentIconEntry('medication', 'remédio'),
    CommitmentIconEntry('vaccine', 'vacina'),
    CommitmentIconEntry('psychology', 'psicólogo terapia'),
    CommitmentIconEntry('spa', 'spa estética massagem'),
    CommitmentIconEntry('self_improvement', 'meditação yoga'),
    CommitmentIconEntry('fitness', 'academia treino'),
    CommitmentIconEntry('directions_run', 'corrida caminhada'),
    CommitmentIconEntry('pool', 'natação piscina'),
    CommitmentIconEntry('directions_bike', 'bicicleta'),
    CommitmentIconEntry('sports', 'futebol'),
    CommitmentIconEntry('sports_basketball', 'basquete'),
    CommitmentIconEntry('sports_tennis', 'tênis'),
    CommitmentIconEntry('sports_martial_arts', 'luta artes marciais'),
  ]),
  CommitmentIconGroup('Trabalho e estudo', [
    CommitmentIconEntry('work', 'trabalho'),
    CommitmentIconEntry('business_center', 'negócios escritório'),
    CommitmentIconEntry('meeting_room', 'reunião sala'),
    CommitmentIconEntry('handshake', 'acordo cliente'),
    CommitmentIconEntry('call', 'ligação telefone'),
    CommitmentIconEntry('videocam', 'videochamada reunião online'),
    CommitmentIconEntry('mail', 'email'),
    CommitmentIconEntry('description', 'documento'),
    CommitmentIconEntry('assignment', 'tarefa formulário'),
    CommitmentIconEntry('gavel', 'audiência justiça'),
    CommitmentIconEntry('balance', 'justiça advogado'),
    CommitmentIconEntry('shield', 'segurança plantão'),
    CommitmentIconEntry('local_police', 'polícia plantão'),
    CommitmentIconEntry('engineering', 'engenheiro técnico'),
    CommitmentIconEntry('construction', 'obra'),
    CommitmentIconEntry('school', 'escola aula'),
    CommitmentIconEntry('menu_book', 'estudo livro'),
    CommitmentIconEntry('auto_stories', 'leitura'),
    CommitmentIconEntry('edit_note', 'anotação prova'),
    CommitmentIconEntry('science', 'laboratório ciência'),
    CommitmentIconEntry('language', 'idioma curso online'),
  ]),
  CommitmentIconGroup('Dinheiro e compras', [
    CommitmentIconEntry('payments', 'pagamento'),
    CommitmentIconEntry('attach_money', 'dinheiro'),
    CommitmentIconEntry('savings', 'poupança cofrinho'),
    CommitmentIconEntry('credit_card', 'cartão fatura'),
    CommitmentIconEntry('bank', 'banco'),
    CommitmentIconEntry('receipt', 'boleto conta recibo'),
    CommitmentIconEntry('request_quote', 'orçamento cobrança'),
    CommitmentIconEntry('trending_up', 'investimento meta'),
    CommitmentIconEntry('shopping', 'mercado'),
    CommitmentIconEntry('shopping_bag', 'compras'),
    CommitmentIconEntry('store', 'loja'),
    CommitmentIconEntry('checkroom', 'roupa'),
    CommitmentIconEntry('local_offer', 'promoção'),
  ]),
  CommitmentIconGroup('Casa e comida', [
    CommitmentIconEntry('home', 'casa'),
    CommitmentIconEntry('key', 'chave aluguel'),
    CommitmentIconEntry('cleaning', 'faxina limpeza'),
    CommitmentIconEntry('local_laundry', 'lavanderia roupa'),
    CommitmentIconEntry('handyman', 'conserto manutenção'),
    CommitmentIconEntry('build', 'ferramenta'),
    CommitmentIconEntry('yard', 'jardim'),
    CommitmentIconEntry('chair', 'móveis'),
    CommitmentIconEntry('local_shipping', 'entrega mudança'),
    CommitmentIconEntry('pets', 'pet veterinário'),
    CommitmentIconEntry('restaurant', 'almoço jantar'),
    CommitmentIconEntry('local_cafe', 'café'),
    CommitmentIconEntry('local_pizza', 'pizza'),
    CommitmentIconEntry('outdoor_grill', 'churrasco'),
    CommitmentIconEntry('local_bar', 'bar bebida'),
    CommitmentIconEntry('bakery', 'padaria pão'),
  ]),
  CommitmentIconGroup('Transporte e lazer', [
    CommitmentIconEntry('car', 'carro'),
    CommitmentIconEntry('two_wheeler', 'moto'),
    CommitmentIconEntry('local_taxi', 'táxi uber'),
    CommitmentIconEntry('directions_bus', 'ônibus'),
    CommitmentIconEntry('train', 'trem metrô'),
    CommitmentIconEntry('flight', 'voo avião viagem'),
    CommitmentIconEntry('local_gas_station', 'combustível posto'),
    CommitmentIconEntry('local_parking', 'estacionamento'),
    CommitmentIconEntry('luggage', 'mala viagem'),
    CommitmentIconEntry('beach', 'praia férias'),
    CommitmentIconEntry('hiking', 'trilha passeio'),
    CommitmentIconEntry('park', 'parque natureza'),
    CommitmentIconEntry('movie', 'cinema filme'),
    CommitmentIconEntry('theater', 'teatro'),
    CommitmentIconEntry('music', 'música show'),
    CommitmentIconEntry('sports_esports', 'videogame'),
    CommitmentIconEntry('camera', 'foto'),
    CommitmentIconEntry('church', 'igreja missa culto'),
  ]),
  CommitmentIconGroup('Tecnologia e clima', [
    CommitmentIconEntry('laptop', 'notebook computador'),
    CommitmentIconEntry('smartphone', 'celular'),
    CommitmentIconEntry('watch', 'relógio'),
    CommitmentIconEntry('print', 'impressora'),
    CommitmentIconEntry('wifi', 'internet'),
    CommitmentIconEntry('lightbulb', 'ideia luz'),
    CommitmentIconEntry('bolt', 'energia urgente'),
    CommitmentIconEntry('wb_sunny', 'sol'),
    CommitmentIconEntry('water_drop', 'água chuva'),
    CommitmentIconEntry('ac_unit', 'frio'),
    CommitmentIconEntry('nightlight', 'noite lua'),
  ]),
  CommitmentIconGroup('Símbolos e alertas', [
    CommitmentIconEntry('event', 'evento data'),
    CommitmentIconEntry('alarm', 'despertador alarme'),
    CommitmentIconEntry('bell', 'aviso lembrete'),
    CommitmentIconEntry('hourglass', 'prazo tempo'),
    CommitmentIconEntry('priority_high', 'importante'),
    CommitmentIconEntry('warning', 'atenção'),
    CommitmentIconEntry('check_circle', 'concluído ok'),
    CommitmentIconEntry('push_pin', 'fixar lembrete'),
    CommitmentIconEntry('place', 'local endereço'),
    CommitmentIconEntry('campaign', 'anúncio'),
    CommitmentIconEntry('chat', 'mensagem'),
    CommitmentIconEntry('lock', 'senha segurança'),
    CommitmentIconEntry('flag', 'meta bandeira'),
  ]),
];

/// Remove acentos e baixa a caixa — busca «aniversario» acha «aniversário».
String commitmentSearchNormalize(String s) {
  const de = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const para = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().runes) {
    final c = String.fromCharCode(ch);
    final i = de.indexOf(c);
    b.write(i >= 0 ? para[i] : c);
  }
  return b.toString().trim();
}

/// Símbolo decodificado do campo `commitmentSymbol`.
@immutable
class CommitmentSymbol {
  const CommitmentSymbol.emoji(String this.emoji) : iconKey = null;
  const CommitmentSymbol.icon(String this.iconKey) : emoji = null;

  final String? emoji;
  final String? iconKey;

  IconData? get icon => iconKey == null ? null : kCommitmentIcons[iconKey];

  /// Valor gravado no Firestore.
  String get raw => emoji != null ? 'emoji:$emoji' : 'icon:$iconKey';

  static CommitmentSymbol? parse(Object? raw) {
    final s = (raw ?? '').toString().trim();
    if (s.startsWith('emoji:') && s.length > 6) {
      return CommitmentSymbol.emoji(s.substring(6));
    }
    if (s.startsWith('icon:')) {
      final k = s.substring(5);
      if (kCommitmentIcons.containsKey(k)) return CommitmentSymbol.icon(k);
    }
    return null;
  }

  static CommitmentSymbol? fromData(Map<String, dynamic>? data) =>
      parse(data?[kCommitmentSymbolField]);

  @override
  bool operator ==(Object other) =>
      other is CommitmentSymbol && other.raw == raw;

  @override
  int get hashCode => raw.hashCode;
}

/// Emoji sugerido pelo título quando o usuário não escolheu nenhum — mesmo
/// critério do bot do Telegram.
String? suggestCommitmentEmoji(String? title) {
  final t = commitmentLabelBaseForMatch(title).toLowerCase();
  if (t.isEmpty) return null;
  const regras = <String, String>{
    'casamento': '💍',
    'noivado': '💍',
    'namoro': '❤️',
    'aniversario': '🎂',
    'aniversário': '🎂',
    'niver': '🎂',
    'formatura': '🎓',
    'natal': '🎄',
    'ano novo': '🎆',
    'reveillon': '🎆',
    'páscoa': '🐣',
    'pascoa': '🐣',
    'dia das maes': '🌹',
    'dia das mães': '🌹',
    'dia dos pais': '👔',
    'falecimento': '🕯️',
    'memoria': '🕯️',
    'memória': '🕯️',
    'batizado': '⛪',
    'bebe': '👶',
    'bebê': '👶',
  };
  for (final e in regras.entries) {
    if (t.contains(e.key)) return e.value;
  }
  return null;
}

/// Widget do símbolo: emoji escolhido, ícone escolhido ou o ícone deduzido do
/// título, nessa ordem.
Widget commitmentSymbolWidget({
  required CommitmentSymbol? symbol,
  required String? title,
  required double size,
  Color? color,
}) {
  if (symbol?.emoji != null) {
    return Text(symbol!.emoji!,
        style: TextStyle(fontSize: size * 0.95, height: 1.0));
  }
  final visual = resolveCommitmentVisual(title);
  return Icon(symbol?.icon ?? visual.icon,
      color: color ?? visual.color, size: size);
}
