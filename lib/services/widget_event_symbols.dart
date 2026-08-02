import 'package:flutter/material.dart';

import '../constants/commitment_presets.dart';

/// Emojis modernos do widget de calendário — inferidos por tipo + título/abreviação.
class WidgetEventSymbols {
  WidgetEventSymbols._();

  static String resolve({
    required String type,
    required String title,
    String abbreviation = '',
  }) {
    final t = type.toLowerCase().trim();
    final hay = _normalize('$title $abbreviation');

    if (t == 'finance') return '💳';
    if (t == 'expense') return '📉';
    if (t == 'income') return '📈';
    if (_matches(hay, _birthdayKeys)) return '🎂';
    if (_matches(hay, _dentistKeys)) return '🦷';
    if (_matches(hay, _doctorKeys)) return '🩺';
    if (_matches(hay, _churchKeys)) return '⛪';
    if (_matches(hay, _weddingKeys)) return '💒';
    if (_matches(hay, _meetingKeys)) return '👥';
    if (_matches(hay, _schoolKeys)) return '🎓';
    if (_matches(hay, _shoppingKeys)) return '🛒';
    if (_matches(hay, _travelKeys)) return '✈️';
    if (_matches(hay, _gymKeys)) return '💪';
    if (_matches(hay, _operationKeys)) return '⚡';
    if (_matches(hay, _vtrKeys)) return '🚓';

    if (t == 'scale' || t == 'plantao' || t == 'plantão') {
      if (_matches(hay, _patrolKeys)) return '👮';
      return '🚔';
    }

    if (t == 'compromisso') {
      // Ícone colorido do preset → emoji correspondente no widget.
      final visual = resolveCommitmentVisual(title);
      return _emojiForCommitmentIcon(visual.icon) ?? '📅';
    }
    return '📌';
  }

  static String? _emojiForCommitmentIcon(IconData icon) {
    if (icon == Icons.biotech_rounded) return '🧪';
    if (icon == Icons.medical_services_rounded) return '🩺';
    if (icon == Icons.medical_information_rounded) return '🦷';
    if (icon == Icons.psychology_rounded) return '🧠';
    if (icon == Icons.vaccines_rounded) return '💉';
    if (icon == Icons.local_pharmacy_rounded) return '💊';
    if (icon == Icons.pets_rounded) return '🐾';
    if (icon == Icons.video_call_rounded) return '💻';
    if (icon == Icons.groups_rounded) return '👥';
    if (icon == Icons.gavel_rounded) return '⚖️';
    if (icon == Icons.handshake_rounded) return '🤝';
    if (icon == Icons.work_history_rounded) return '👮';
    if (icon == Icons.restaurant_rounded) return '🍽️';
    if (icon == Icons.event_available_rounded) return '📅';
    if (icon == Icons.school_rounded) return '🎓';
    if (icon == Icons.menu_book_rounded) return '📚';
    if (icon == Icons.co_present_rounded) return '👨‍🏫';
    if (icon == Icons.auto_stories_rounded) return '📖';
    if (icon == Icons.directions_car_rounded) return '🚗';
    if (icon == Icons.cake_rounded) return '🎂';
    if (icon == Icons.favorite_rounded) return '💒';
    if (icon == Icons.family_restroom_rounded) return '👨‍👩‍👧‍👦';
    if (icon == Icons.checklist_rounded) return '✅';
    if (icon == Icons.cleaning_services_rounded) return '🧹';
    if (icon == Icons.shopping_cart_rounded) return '🛒';
    if (icon == Icons.account_balance_rounded) return '🏦';
    if (icon == Icons.receipt_long_rounded) return '🧾';
    if (icon == Icons.payments_rounded) return '💳';
    if (icon == Icons.shopping_bag_rounded) return '🛍️';
    if (icon == Icons.local_shipping_rounded) return '📦';
    if (icon == Icons.build_rounded) return '🔧';
    if (icon == Icons.car_repair_rounded) return '🛠️';
    if (icon == Icons.local_car_wash_rounded) return '🚿';
    if (icon == Icons.content_cut_rounded) return '💇';
    if (icon == Icons.fitness_center_rounded) return '💪';
    if (icon == Icons.sports_soccer_rounded) return '⚽';
    if (icon == Icons.weekend_rounded) return '🛋️';
    if (icon == Icons.flight_takeoff_rounded) return '✈️';
    if (icon == Icons.church_rounded) return '⛪';
    if (icon == Icons.assignment_ind_rounded) return '🪪';
    return null;
  }

  /// Cor da barra lateral quando o evento não traz accent próprio.
  static String defaultBarHex({
    required String type,
    required String symbol,
    required bool isToday,
  }) {
    switch (symbol) {
      case '🎂':
        return '#FFEC407A';
      case '🩺':
        return '#FF26A69A';
      case '🦷':
        return '#FF42A5F5';
      case '⚖️':
        return '#FF7C4DFF';
      case '🚓':
        return '#FF2563EB';
      case '👮':
        return '#FF00BCD4';
      case '⚡':
        return '#FFFFB300';
      case '⛪':
        return '#FF8D6E63';
      case '💒':
        return '#FFE91E63';
      case '👥':
        return '#FF1E88E5';
      case '🎓':
        return '#FF5C6BC0';
      case '💳':
        return '#FFFF8A50';
      case '📉':
        return '#FFFF5252';
      case '📈':
        return '#FF4CAF50';
      case '📅':
        return '#FF12B5A5';
      default:
        break;
    }
    switch (type.toLowerCase()) {
      case 'compromisso':
        return '#FF12B5A5';
      case 'finance':
        return '#FFFF8A50';
      case 'expense':
        return '#FFFF5252';
      case 'income':
        return '#FF4CAF50';
      default:
        return isToday ? '#FF00BCD4' : '#FFFFC107';
    }
  }

  static String _normalize(String raw) {
    return raw
        .toLowerCase()
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

  static bool _matches(String hay, List<String> keys) {
    for (final k in keys) {
      if (hay.contains(k)) return true;
    }
    return false;
  }

  static const _birthdayKeys = [
    'anivers',
    'birthday',
    'bolo',
    'festa de aniv',
  ];

  static const _dentistKeys = [
    'dentist',
    'odonto',
    'ortodont',
  ];

  static const _doctorKeys = [
    'medico',
    'medic',
    'consulta med',
    'hospital',
    'clinica',
    'exame',
    'laborator',
    'psicolog',
    'terapia',
    'vacina',
    'farmacia',
    'veterin',
    'dermatolog',
    'oftalmolog',
    'cardiolog',
    'neurolog',
    'fisioter',
    'nutricion',
  ];

  static const _vtrKeys = [
    'vtr',
    'viatura',
    'patrulh',
    'bpm',
    'sv.',
    'sv ',
    'servico viatura',
  ];

  static const _patrolKeys = [
    'plantao',
    'escala',
    'ordin',
    'extra',
    'servico',
    'turno',
    'ronda',
  ];

  static const _operationKeys = [
    'operac',
    'equipe de oper',
    'tatico',
    'coe',
    'rotam',
  ];

  static const _churchKeys = ['igreja', 'culto', 'missa'];
  static const _weddingKeys = ['casamento', 'noiv', 'matrim'];
  static const _meetingKeys = ['reuniao', 'meeting', 'networking'];
  static const _schoolKeys = [
    'escola',
    'faculdade',
    'curso',
    'aula',
    'prova',
    'vestibular',
  ];
  static const _shoppingKeys = [
    'mercado',
    'supermercado',
    'compras',
    'shopping',
    'banco',
    'conta',
  ];
  static const _travelKeys = ['viagem', 'aeroporto', 'hotel', 'onibus'];
  static const _gymKeys = ['academia', 'treino', 'corrida', 'natacao'];
}
