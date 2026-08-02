import 'package:flutter/material.dart';

/// Categoria visual de um compromisso (ícone + cor) para a UX premium do
/// "Compromisso expresso".
@immutable
class CommitmentPreset {
  /// Nome exibido (também usado como descrição automática quando o usuário
  /// toca num ícone rápido ou seleciona da lista).
  final String name;

  /// Ícone Material moderno para representar o compromisso.
  final IconData icon;

  /// Cor base do ícone (e do chip do calendário, quando o usuário não escolher
  /// outra). Tons fortes e modernos — premium.
  final Color color;

  const CommitmentPreset({
    required this.name,
    required this.icon,
    required this.color,
  });
}

/// Os 6 atalhos rápidos no topo do card de Identificação (mais comuns).
/// Toque preenche a descrição automaticamente — o usuário só ajusta horário
/// e cor. Coloridos, modernos, padrão super premium.
const List<CommitmentPreset> kCommitmentQuickPresets = [
  CommitmentPreset(name: 'Reunião de trabalho', icon: Icons.groups_rounded, color: Color(0xFF1E88E5)),
  CommitmentPreset(name: 'Consulta médica', icon: Icons.medical_services_rounded, color: Color(0xFF26A69A)),
  CommitmentPreset(name: 'Dentista', icon: Icons.medical_information_rounded, color: Color(0xFF42A5F5)),
  CommitmentPreset(name: 'Igreja/culto', icon: Icons.church_rounded, color: Color(0xFF8D6E63)),
  CommitmentPreset(name: 'Aniversários', icon: Icons.cake_rounded, color: Color(0xFFEC407A)),
  CommitmentPreset(name: 'Casamento', icon: Icons.favorite_rounded, color: Color(0xFFE91E63)),
];

/// Lista oficial de compromissos para a sugestão (mesma lista enviada pelo
/// usuário, ordem original — a UI ordena alfabeticamente). Os ícones e cores
/// são atribuídos por categoria — ajuda a varredura visual da lista.
const List<CommitmentPreset> kCommitmentPresets = [
  // Saúde
  CommitmentPreset(name: 'Consulta médica', icon: Icons.medical_services_rounded, color: Color(0xFF26A69A)),
  CommitmentPreset(name: 'Dentista', icon: Icons.medical_information_rounded, color: Color(0xFF42A5F5)),
  CommitmentPreset(name: 'Exames laboratoriais', icon: Icons.biotech_rounded, color: Color(0xFF7E57C2)),
  CommitmentPreset(name: 'Psicólogo/Terapia', icon: Icons.psychology_rounded, color: Color(0xFF7E57C2)),
  CommitmentPreset(name: 'Vacinação', icon: Icons.vaccines_rounded, color: Color(0xFF66BB6A)),
  CommitmentPreset(name: 'Farmácia', icon: Icons.local_pharmacy_rounded, color: Color(0xFF66BB6A)),
  CommitmentPreset(name: 'Veterinário', icon: Icons.pets_rounded, color: Color(0xFFAB47BC)),
  CommitmentPreset(name: 'Consulta online', icon: Icons.video_call_rounded, color: Color(0xFF26A69A)),

  // Trabalho
  CommitmentPreset(name: 'Reunião de trabalho', icon: Icons.groups_rounded, color: Color(0xFF1E88E5)),
  CommitmentPreset(name: 'Consulta jurídica/advogado', icon: Icons.gavel_rounded, color: Color(0xFF455A64)),
  CommitmentPreset(name: 'Entrevista de emprego', icon: Icons.handshake_rounded, color: Color(0xFF1E88E5)),
  CommitmentPreset(name: 'Plantão/escala de serviço', icon: Icons.work_history_rounded, color: Color(0xFF1A237E)),
  CommitmentPreset(name: 'Almoço/jantar de negócios', icon: Icons.restaurant_rounded, color: Color(0xFFFB8C00)),
  CommitmentPreset(name: 'Networking/eventos', icon: Icons.event_available_rounded, color: Color(0xFF1E88E5)),

  // Educação
  CommitmentPreset(name: 'Escola/faculdade', icon: Icons.school_rounded, color: Color(0xFF5C6BC0)),
  CommitmentPreset(name: 'Curso', icon: Icons.menu_book_rounded, color: Color(0xFF5C6BC0)),
  CommitmentPreset(name: 'Reunião escolar', icon: Icons.co_present_rounded, color: Color(0xFF5C6BC0)),
  CommitmentPreset(name: 'Revisão de estudos', icon: Icons.auto_stories_rounded, color: Color(0xFF5C6BC0)),

  // Família e casa
  CommitmentPreset(name: 'Buscar filhos na escola', icon: Icons.directions_car_rounded, color: Color(0xFFFB8C00)),
  CommitmentPreset(name: 'Aniversários', icon: Icons.cake_rounded, color: Color(0xFFEC407A)),
  CommitmentPreset(name: 'Casamento', icon: Icons.favorite_rounded, color: Color(0xFFE91E63)),
  CommitmentPreset(name: 'Passeio/família', icon: Icons.family_restroom_rounded, color: Color(0xFFEC407A)),
  CommitmentPreset(name: 'Organização doméstica', icon: Icons.checklist_rounded, color: Color(0xFF8D6E63)),
  CommitmentPreset(name: 'Limpeza da casa', icon: Icons.cleaning_services_rounded, color: Color(0xFF8D6E63)),

  // Compras e contas
  CommitmentPreset(name: 'Mercado/supermercado', icon: Icons.shopping_cart_rounded, color: Color(0xFF66BB6A)),
  CommitmentPreset(name: 'Banco', icon: Icons.account_balance_rounded, color: Color(0xFF1A237E)),
  CommitmentPreset(name: 'Pagamento de contas', icon: Icons.receipt_long_rounded, color: Color(0xFFEF5350)),
  CommitmentPreset(name: 'Compromissos financeiros', icon: Icons.payments_rounded, color: Color(0xFFEF5350)),
  CommitmentPreset(name: 'Compras pessoais', icon: Icons.shopping_bag_rounded, color: Color(0xFFFB8C00)),
  CommitmentPreset(name: 'Entregas/encomendas', icon: Icons.local_shipping_rounded, color: Color(0xFFFB8C00)),

  // Veículos / pessoal
  CommitmentPreset(name: 'Manutenção do carro/moto', icon: Icons.build_rounded, color: Color(0xFF455A64)),
  CommitmentPreset(name: 'Oficina mecânica', icon: Icons.car_repair_rounded, color: Color(0xFF455A64)),
  CommitmentPreset(name: 'Lava-jato', icon: Icons.local_car_wash_rounded, color: Color(0xFF42A5F5)),
  CommitmentPreset(name: 'Salão/barbearia', icon: Icons.content_cut_rounded, color: Color(0xFFAB47BC)),

  // Esporte / lazer
  CommitmentPreset(name: 'Academia', icon: Icons.fitness_center_rounded, color: Color(0xFFEF6C00)),
  CommitmentPreset(name: 'Treino esportivo', icon: Icons.sports_soccer_rounded, color: Color(0xFFEF6C00)),
  CommitmentPreset(name: 'Descanso/lazer', icon: Icons.weekend_rounded, color: Color(0xFFEC407A)),
  CommitmentPreset(name: 'Viagens', icon: Icons.flight_takeoff_rounded, color: Color(0xFF1E88E5)),

  // Religião
  CommitmentPreset(name: 'Igreja/culto', icon: Icons.church_rounded, color: Color(0xFF8D6E63)),

  // Documentos
  CommitmentPreset(name: 'Renovação de documentos', icon: Icons.assignment_ind_rounded, color: Color(0xFF455A64)),
  CommitmentPreset(name: 'Cartório', icon: Icons.gavel_rounded, color: Color(0xFF455A64)),
];

/// Mapa de descrição → preset para resolver ícone/cor a partir do nome.
final Map<String, CommitmentPreset> kCommitmentPresetByName = {
  for (final p in kCommitmentPresets) p.name.toLowerCase().trim(): p,
};

String _normalizeCommitmentKey(String raw) {
  return raw
      .toLowerCase()
      .trim()
      .replaceAll('á', 'a')
      .replaceAll('à', 'a')
      .replaceAll('â', 'a')
      .replaceAll('ã', 'a')
      .replaceAll('é', 'e')
      .replaceAll('ê', 'e')
      .replaceAll('í', 'i')
      .replaceAll('ó', 'o')
      .replaceAll('ô', 'o')
      .replaceAll('õ', 'o')
      .replaceAll('ú', 'u')
      .replaceAll('ç', 'c');
}

/// Remove «Compromisso » do início (exibição / match de ícone).
String stripLeadingCompromissoWord(String raw) {
  var l = raw.trim();
  if (l.isEmpty) return l;
  return l
      .replaceFirst(RegExp(r'^compromisso\s+', caseSensitive: false), '')
      .trim();
}

/// Nome “limpo” para match: sem prefixo Compromisso, sem horário/horas no fim.
String commitmentLabelBaseForMatch(String? raw) {
  var n = stripLeadingCompromissoWord(raw ?? '');
  if (n.isEmpty) return '';
  n = n
      .replaceFirst(
        RegExp(r'\s+\d+([,.]\d+)?\s+HORAS\s*$', caseSensitive: false),
        '',
      )
      .trim();
  final match = RegExp(
    r'\s+\d{1,2}:\d{2}\s*[àa]s\s*\d{1,2}:\d{2}\s*$',
    caseSensitive: false,
  ).firstMatch(n);
  if (match != null) n = n.substring(0, match.start).trim();
  return n;
}

const List<Color> _kCommitmentFallbackColors = [
  Color(0xFF1E88E5),
  Color(0xFF26A69A),
  Color(0xFF7E57C2),
  Color(0xFFEF6C00),
  Color(0xFFEC407A),
  Color(0xFF5C6BC0),
  Color(0xFF00897B),
  Color(0xFFFB8C00),
  Color(0xFFAB47BC),
  Color(0xFF42A5F5),
];

const List<IconData> _kCommitmentFallbackIcons = [
  Icons.event_available_rounded,
  Icons.star_rounded,
  Icons.bookmark_rounded,
  Icons.place_rounded,
  Icons.schedule_rounded,
  Icons.flag_rounded,
  Icons.lightbulb_rounded,
  Icons.favorite_rounded,
];

/// Resolve ícone/cor do compromisso (presets oficiais + fallback colorido estável).
CommitmentPreset resolveCommitmentVisual(String? rawLabel) {
  final base = commitmentLabelBaseForMatch(rawLabel);
  final key = _normalizeCommitmentKey(base);
  if (key.isEmpty) {
    return const CommitmentPreset(
      name: 'Compromisso',
      icon: Icons.event_available_rounded,
      color: Color(0xFF12B5A5),
    );
  }

  final exact = kCommitmentPresetByName[key];
  if (exact != null) return exact;

  CommitmentPreset? best;
  var bestLen = 0;
  for (final p in kCommitmentPresets) {
    final pn = _normalizeCommitmentKey(p.name);
    if (pn.isEmpty) continue;
    if (key.contains(pn) || pn.contains(key)) {
      if (pn.length > bestLen) {
        best = p;
        bestLen = pn.length;
      }
    }
  }
  if (best != null) return best;

  final hash = key.hashCode.abs();
  return CommitmentPreset(
    name: base,
    icon: _kCommitmentFallbackIcons[hash % _kCommitmentFallbackIcons.length],
    color: _kCommitmentFallbackColors[hash % _kCommitmentFallbackColors.length],
  );
}
