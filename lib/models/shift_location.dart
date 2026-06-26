import 'package:flutter/material.dart';

/// Tipo de vínculo (estado, município, particular).
enum EmployerType { state, municipality, private }

/// Pagamento por hora (usa parâmetros do sistema) ou valor fixo por plantão/dia.
enum PaymentType { perHour, fixed }

/// Local/tipo de plantão: nome, cor no calendário, horário padrão, modo financeiro e adicional noturno.
class ShiftLocation {
  final String? id;
  final String name;
  final String abbreviation;
  /// Cor em hex (ex: "0xFF2D5BFF") para calendário e gráficos.
  final String colorHex;
  /// Horário padrão início "HH:mm"
  final String startTime;
  /// Horário padrão fim "HH:mm"
  final String endTime;
  final bool notifyEnabled;
  final bool financialEnabled;
  final PaymentType paymentType;
  final EmployerType employerType;
  final double baseValue;
  final double bonus;
  final double discount;
  final bool nightDifferentialEnabled;
  /// Ex: 20 para 20%
  final double nightDifferentialPercent;
  /// Ex: "22:00"
  final String nightStart;
  /// Ex: "05:00"
  final String nightEnd;
  final int sortOrder;
  /// Antecedências em minutos para notificações locais; null ou vazio = usa padrão global.
  final List<int>? reminderLeads;

  /// `id` do banco offline de toques (`notification_sound_catalog.dart`).
  /// `null` ou vazio = usa o som padrão da categoria (Preferências → Sons).
  /// Vale como **padrão de notificação** quando um plantão é lançado a
  /// partir deste pré-cadastro recorrente.
  final String? notificationSoundId;

  /// Modo de entrega (`audio`/`vibrate`/`push`) padrão deste plantão recorrente.
  /// `null` ou vazio = herda o padrão global do usuário (Preferências).
  final String? notificationDeliveryMode;

  const ShiftLocation({
    this.id,
    required this.name,
    required this.abbreviation,
    this.colorHex = '0xFF2D5BFF',
    this.startTime = '08:00',
    this.endTime = '18:00',
    this.notifyEnabled = true,
    this.financialEnabled = false,
    this.paymentType = PaymentType.perHour,
    this.employerType = EmployerType.private,
    this.baseValue = 0,
    this.bonus = 0,
    this.discount = 0,
    this.nightDifferentialEnabled = false,
    this.nightDifferentialPercent = 20,
    this.nightStart = '22:00',
    this.nightEnd = '05:00',
    this.sortOrder = 0,
    this.reminderLeads,
    this.notificationSoundId,
    this.notificationDeliveryMode,
  });

  Color get color {
    try {
      var hex = colorHex.replaceFirst('#', '').replaceFirst('0x', '').trim();
      if (hex.length > 8) hex = hex.substring(0, 8);
      if (hex.length < 6) return const Color(0xFF2D5BFF);
      return Color(int.parse(hex, radix: 16));
    } catch (_) {
      return const Color(0xFF2D5BFF);
    }
  }

  ShiftLocation copyWith({
    String? id,
    String? name,
    String? abbreviation,
    String? colorHex,
    String? startTime,
    String? endTime,
    bool? notifyEnabled,
    bool? financialEnabled,
    PaymentType? paymentType,
    EmployerType? employerType,
    double? baseValue,
    double? bonus,
    double? discount,
    bool? nightDifferentialEnabled,
    double? nightDifferentialPercent,
    String? nightStart,
    String? nightEnd,
    int? sortOrder,
    List<int>? reminderLeads,
    String? notificationSoundId,
    String? notificationDeliveryMode,
    bool clearNotificationSound = false,
    bool clearNotificationDeliveryMode = false,
  }) {
    return ShiftLocation(
      id: id ?? this.id,
      name: name ?? this.name,
      abbreviation: abbreviation ?? this.abbreviation,
      colorHex: colorHex ?? this.colorHex,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      notifyEnabled: notifyEnabled ?? this.notifyEnabled,
      financialEnabled: financialEnabled ?? this.financialEnabled,
      paymentType: paymentType ?? this.paymentType,
      employerType: employerType ?? this.employerType,
      baseValue: baseValue ?? this.baseValue,
      bonus: bonus ?? this.bonus,
      discount: discount ?? this.discount,
      nightDifferentialEnabled: nightDifferentialEnabled ?? this.nightDifferentialEnabled,
      nightDifferentialPercent: nightDifferentialPercent ?? this.nightDifferentialPercent,
      nightStart: nightStart ?? this.nightStart,
      nightEnd: nightEnd ?? this.nightEnd,
      sortOrder: sortOrder ?? this.sortOrder,
      reminderLeads: reminderLeads ?? this.reminderLeads,
      notificationSoundId: clearNotificationSound
          ? null
          : (notificationSoundId ?? this.notificationSoundId),
      notificationDeliveryMode: clearNotificationDeliveryMode
          ? null
          : (notificationDeliveryMode ?? this.notificationDeliveryMode),
    );
  }

  Map<String, dynamic> toMap() => {
        'name': name,
        'abbreviation': abbreviation,
        'colorHex': colorHex,
        'startTime': startTime,
        'endTime': endTime,
        'notifyEnabled': notifyEnabled,
        'financialEnabled': financialEnabled,
        'paymentType': paymentType.name,
        'employerType': employerType.name,
        'baseValue': baseValue,
        'bonus': bonus,
        'discount': discount,
        'nightDifferentialEnabled': nightDifferentialEnabled,
        'nightDifferentialPercent': nightDifferentialPercent,
        'nightStart': nightStart,
        'nightEnd': nightEnd,
        'sortOrder': sortOrder,
        if (reminderLeads != null && reminderLeads!.isNotEmpty)
          'reminderLeads': reminderLeads,
        if (notificationSoundId != null && notificationSoundId!.isNotEmpty)
          'notificationSoundId': notificationSoundId,
        if (notificationDeliveryMode != null &&
            notificationDeliveryMode!.isNotEmpty)
          'notificationDeliveryMode': notificationDeliveryMode,
      };

  /// Um segmento da sigla a partir de um token (ex.: `4º` → `4`, `BPM` → `B`).
  static String _abbrevChunkFromToken(String token) {
    final t = token.trim().toUpperCase();
    if (t.isEmpty) return '';
    final digitMatch = RegExp(r'^(\d+)').firstMatch(t);
    if (digitMatch != null) {
      final digits = digitMatch.group(1)!;
      return digits.length > 6 ? digits.substring(0, 6) : digits;
    }
    for (final r in t.runes) {
      final ch = String.fromCharCode(r);
      if (RegExp(r'[A-ZÁÀÂÃÄÅÆÇÉÈÊËÍÌÎÏÑÓÒÔÕÖÚÙÛÜÝ]', caseSensitive: false)
          .hasMatch(ch)) {
        return ch.toUpperCase();
      }
    }
    return '';
  }

  /// Gera iniciais a partir do nome quando a sigla está vazia: até 6 caracteres, sempre maiúsculas.
  /// Usa somente a parte com letras (base), ignora o complemento de horário " HH:MM ÀS HH:MM".
  /// Várias palavras: primeira letra (ou bloco numérico inicial) de cada token — ex. `REFORÇO 4º BPM` → `R4B`.
  static String abbreviationFromName(String name) {
    final base = baseNameFromFull(name.trim());
    final n = base.toUpperCase();
    if (n.isEmpty) return '';
    final words =
        n.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.length >= 2) {
      final sb = StringBuffer();
      for (final w in words) {
        if (sb.length >= 6) break;
        final chunk = _abbrevChunkFromToken(w);
        if (chunk.isEmpty) continue;
        final remaining = 6 - sb.length;
        sb.write(chunk.length <= remaining ? chunk : chunk.substring(0, remaining));
      }
      return sb.toString();
    }
    return n.length > 6 ? n.substring(0, 6) : n;
  }

  /// Remove sufixo de horário " HH:MM às HH:MM" do nome, se existir.
  static String baseNameFromFull(String name) {
    final n = name.trim();
    if (n.isEmpty) return n;
    final match = RegExp(r'\s+\d{1,2}:\d{2}\s*[àa]s\s*\d{1,2}:\d{2}\s*$', caseSensitive: false).firstMatch(n);
    if (match != null) {
      return n.substring(0, match.start).trim();
    }
    return n;
  }

  /// Retorna nome completo com horário: "BASE HH:MM ÀS HH:MM". Facilita relatórios.
  static String fullNameWithSchedule(String baseName, String startTime, String endTime) {
    final base = baseNameFromFull(baseName.trim());
    final start = startTime.trim();
    final end = endTime.trim();
    if (start.isEmpty || end.isEmpty) return base.isEmpty ? 'PLANTÃO' : base;
    final baseUpper = base.isEmpty ? 'PLANTÃO' : base.toUpperCase();
    return '$baseUpper $start ÀS $end';
  }

  static ShiftLocation fromMap(String? id, Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) {
      return ShiftLocation(id: id, name: '', abbreviation: '');
    }
    var nameRaw = (data['name'] ?? '').toString().trim().toUpperCase();
    if (nameRaw.isEmpty) {
      final fall = (data['label'] ?? data['title'] ?? '')
          .toString()
          .trim()
          .toUpperCase();
      if (fall.isNotEmpty) nameRaw = fall;
    }
    var abbrRaw = (data['abbreviation'] ?? '').toString().trim().toUpperCase();
    if (abbrRaw.length > 6) abbrRaw = abbrRaw.substring(0, 6);
    if (abbrRaw.isEmpty && nameRaw.isNotEmpty) {
      abbrRaw = abbreviationFromName(nameRaw);
    }
    // Legado / pós-UI sem campo nome visível: documento só com sigla gravada — manter plantão na lista e escalas.
    if (nameRaw.isEmpty && abbrRaw.isNotEmpty) {
      nameRaw = abbrRaw;
    }
    List<int>? reminderLeadsParsed;
    final rawRl = data['reminderLeads'];
    if (rawRl is List && rawRl.isNotEmpty) {
      reminderLeadsParsed = rawRl
          .map((e) => e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0)
          .where((m) => m > 0)
          .toList();
      if (reminderLeadsParsed.isEmpty) reminderLeadsParsed = null;
    }
    return ShiftLocation(
      id: id,
      name: nameRaw,
      abbreviation: abbrRaw,
      colorHex: _normalizeColorHex((data['colorHex'] ?? '0xFF2D5BFF').toString()),
      startTime: (data['startTime'] ?? '08:00').toString(),
      endTime: (data['endTime'] ?? '18:00').toString(),
      notifyEnabled: data['notifyEnabled'] != false,
      financialEnabled: data['financialEnabled'] == true,
      paymentType: data['paymentType'] == 'fixed' ? PaymentType.fixed : PaymentType.perHour,
      employerType: _parseEmployerType(data['employerType']),
      baseValue: (data['baseValue'] is num) ? (data['baseValue'] as num).toDouble() : double.tryParse(data['baseValue']?.toString() ?? '') ?? 0,
      bonus: (data['bonus'] is num) ? (data['bonus'] as num).toDouble() : double.tryParse(data['bonus']?.toString() ?? '') ?? 0,
      discount: (data['discount'] is num) ? (data['discount'] as num).toDouble() : double.tryParse(data['discount']?.toString() ?? '') ?? 0,
      nightDifferentialEnabled: data['nightDifferentialEnabled'] == true,
      nightDifferentialPercent: (data['nightDifferentialPercent'] is num) ? (data['nightDifferentialPercent'] as num).toDouble() : double.tryParse(data['nightDifferentialPercent']?.toString() ?? '') ?? 20,
      nightStart: (data['nightStart'] ?? '22:00').toString(),
      nightEnd: (data['nightEnd'] ?? '05:00').toString(),
      sortOrder: (data['sortOrder'] is int) ? data['sortOrder'] as int : int.tryParse(data['sortOrder']?.toString() ?? '') ?? 0,
      reminderLeads: reminderLeadsParsed,
      notificationSoundId:
          (data['notificationSoundId'] ?? '').toString().trim().isEmpty
              ? null
              : (data['notificationSoundId'] ?? '').toString().trim(),
      notificationDeliveryMode:
          (data['notificationDeliveryMode'] ?? '').toString().trim().isEmpty
              ? null
              : (data['notificationDeliveryMode'] ?? '').toString().trim(),
    );
  }

  static String _normalizeColorHex(String raw) {
    try {
      var s = raw.trim();
      if (s.isEmpty) return '0xFF2D5BFF';
      if (s.startsWith('#')) {
        final h = s.substring(1);
        if (h.length == 6) {
          int.parse(h, radix: 16);
          return '0xFF$h';
        }
      }
      var hex = s.replaceFirst(RegExp(r'^#'), '').replaceFirst(RegExp(r'^0x', caseSensitive: false), '');
      if (hex.length == 6) {
        int.parse(hex, radix: 16);
        return '0xFF$hex';
      }
      if (hex.length == 8) {
        int.parse(hex, radix: 16);
        return '0x$hex';
      }
    } catch (_) {}
    return '0xFF2D5BFF';
  }

  static EmployerType _parseEmployerType(dynamic v) {
    if (v == null) return EmployerType.private;
    final s = v.toString().toLowerCase();
    if (s == 'state' || s == 'estado') return EmployerType.state;
    if (s == 'municipality' || s == 'municipio') return EmployerType.municipality;
    return EmployerType.private;
  }

  static String employerTypeLabel(EmployerType t) {
    switch (t) {
      case EmployerType.state: return 'Estado';
      case EmployerType.municipality: return 'Município';
      case EmployerType.private: return 'Particular';
    }
  }
}
