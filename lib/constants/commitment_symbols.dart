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

class CommitmentEmojiGroup {
  const CommitmentEmojiGroup(this.titulo, this.emojis);
  final String titulo;
  final List<String> emojis;
}

const List<CommitmentEmojiGroup> kCommitmentEmojiGroups = [
  CommitmentEmojiGroup('Datas especiais', [
    '🎂', '🎉', '🥳', '🎁', '🎈', '🍰', '💍', '💒', '❤️', '💕', '🌹',
    '👰', '🤵', '👶', '🍼', '🎓', '🏆', '🎄', '🎆', '🐣', '🕯️', '⭐',
  ]),
  CommitmentEmojiGroup('Família e casa', [
    '👨‍👩‍👧', '👪', '🏠', '🧹', '🧺', '🛒', '🍽️', '☕', '🐶', '🐱', '🌱',
    '🔑',
  ]),
  CommitmentEmojiGroup('Saúde', [
    '🏥', '🩺', '🦷', '💉', '💊', '🧠', '🏋️', '🧘', '🏃', '🥗',
  ]),
  CommitmentEmojiGroup('Trabalho e estudo', [
    '💼', '🤝', '📊', '💻', '📞', '📚', '✏️', '⚖️', '🏛️', '🚓', '🛡️',
    '📄',
  ]),
  CommitmentEmojiGroup('Dinheiro e contas', [
    '💰', '💳', '🏦', '🧾', '📈', '🪙',
  ]),
  CommitmentEmojiGroup('Lazer e viagem', [
    '✈️', '🏖️', '🚗', '🏍️', '⛺', '🎬', '🎵', '🎮', '⚽', '🎣', '⛪', '🙏',
  ]),
  CommitmentEmojiGroup('Lembretes', [
    '📅', '⏰', '🔔', '📌', '✅', '⚠️', '🔧', '🚿', '📦', '✂️',
  ]),
];

/// Ícones modernos (Material arredondados) por chave estável.
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
};

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
