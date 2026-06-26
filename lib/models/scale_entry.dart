import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'shift_location.dart';
import '../utils/scale_entry_sei_ocorrencia.dart';

/// Pré-cadastro que corresponde ao plantão (nome base ou sigla). Mesma regra da tela Escalas / painel.
ShiftLocation? matchShiftLocationForScaleEntry(
    ScaleEntry e, List<ShiftLocation> locations) {
  final labelBase = (e.label ?? '').trim().toUpperCase();
  final abbr = (e.abbreviation ?? '').trim().toUpperCase();
  if (labelBase.isEmpty && abbr.isEmpty) return null;
  for (final loc in locations) {
    final nameBase = ShiftLocation.baseNameFromFull(loc.name).toUpperCase();
    final locAbbr = loc.abbreviation.trim().toUpperCase();
    if (nameBase.isNotEmpty &&
        (labelBase.contains(nameBase) || nameBase.contains(labelBase)))
      return loc;
    if (locAbbr.isNotEmpty && (abbr == locAbbr || labelBase.contains(locAbbr)))
      return loc;
  }
  return null;
}

/// Uma entrada na escala: plantão pago, não pago ou compromisso.
class ScaleEntry {
  final String? id;
  final DateTime date;
  final String start; // "HH:mm"
  final String end;
  final double dayRate;
  final double nightRate;
  final double hoursDay;
  final double hoursNight;
  final double totalValue;
  final String? notes;

  /// Número da escala (informação adicional para o usuário).
  final String? scaleNumber;

  /// Audiência espelhada da Agenda — número SEI (processo).
  final String? numeroSei;

  /// Audiência espelhada — número de ocorrência.
  final String? numeroOcorrencia;

  /// `audiencia` | `compromisso` quando [isAgendaMirror].
  final String? agendaType;

  /// Espelho criado pelo módulo Agenda.
  final bool isAgendaMirror;

  /// Espelho «Folga · Produtividade» (módulo Ocorrências).
  final bool isProdutividadeFolgaMirror;

  /// Nome da frente de serviço (ex: "Ordinário", "Reforço").
  final String? label;

  /// Iniciais/sigla do plantão (ex: "CASE", "ORDCPU") — usada em badges e notificações.
  final String? abbreviation;

  /// Cor em hex (ex: "#2D5BFF").
  final String? colorHex;

  /// true = plantão pago/hora extra; false = não pago.
  final bool paid;

  /// true = compromisso particular (não é plantão profissional).
  final bool isCompromisso;

  /// Vínculo do plantão: 'state' | 'municipality' | 'private' (Estado, Município, Particular).
  final String? employerType;

  /// Lembrete ou aviso sobre o serviço.
  final String? reminder;

  /// Antecedências dos avisos em minutos (ex: [60, 1440] = 1h e 1 dia antes). Vazio = usa padrão global.
  final List<int>? reminderLeads;

  /// `id` do banco offline de sons (`notification_sound_catalog.dart`) — só
  /// para este plantão/compromisso. `null` = usa o som padrão da categoria.
  final String? notificationSoundId;

  /// Modo de entrega (`audio`/`vibrate`/`push`) só para este plantão. `null`
  /// = herda o padrão da categoria.
  final String? notificationDeliveryMode;

  /// Origem de criação/edição do lançamento (ex.: lançamento expresso).
  final String? source;
  final String? lancamentoOrigem;
  final bool createdByLancamentoExpresso;

  const ScaleEntry({
    this.id,
    required this.date,
    required this.start,
    required this.end,
    this.dayRate = 0,
    this.nightRate = 0,
    this.hoursDay = 0,
    this.hoursNight = 0,
    this.totalValue = 0,
    this.notes,
    this.scaleNumber,
    this.numeroSei,
    this.numeroOcorrencia,
    this.agendaType,
    this.isAgendaMirror = false,
    this.isProdutividadeFolgaMirror = false,
    this.label,
    this.abbreviation,
    this.colorHex,
    this.paid = true,
    this.isCompromisso = false,
    this.employerType,
    this.reminder,
    this.reminderLeads,
    this.notificationSoundId,
    this.notificationDeliveryMode,
    this.source,
    this.lancamentoOrigem,
    this.createdByLancamentoExpresso = false,
  });

  ScaleEntry copyWith({String? notes}) {
    return ScaleEntry(
      id: id,
      date: date,
      start: start,
      end: end,
      dayRate: dayRate,
      nightRate: nightRate,
      hoursDay: hoursDay,
      hoursNight: hoursNight,
      totalValue: totalValue,
      notes: notes ?? this.notes,
      scaleNumber: scaleNumber,
      numeroSei: numeroSei,
      numeroOcorrencia: numeroOcorrencia,
      agendaType: agendaType,
      isAgendaMirror: isAgendaMirror,
      isProdutividadeFolgaMirror: isProdutividadeFolgaMirror,
      label: label,
      abbreviation: abbreviation,
      colorHex: colorHex,
      paid: paid,
      isCompromisso: isCompromisso,
      employerType: employerType,
      reminder: reminder,
      reminderLeads: reminderLeads,
      notificationSoundId: notificationSoundId,
      notificationDeliveryMode: notificationDeliveryMode,
      source: source,
      lancamentoOrigem: lancamentoOrigem,
      createdByLancamentoExpresso: createdByLancamentoExpresso,
    );
  }

  bool get isLancamentoExpresso {
    final src = (source ?? '').trim().toLowerCase();
    final origem = (lancamentoOrigem ?? '').trim().toLowerCase();
    return createdByLancamentoExpresso ||
        src == 'lancamento_expresso' ||
        origem == 'lancamento_expresso';
  }

  /// Mesma regra do painel inicial: vínculo Estado/Município/Particular **e** valor > 0.
  bool get temFinanceiroHabilitadoNoPainel {
    if (isCompromisso) return false;
    final et = employerType;
    return (et == 'state' || et == 'municipality' || et == 'private') &&
        totalValue > 0;
  }

  /// Inclui plantão ligado a pré-cadastro com [ShiftLocation.financialEnabled] (mesmo sem [employerType] salvo).
  bool temFinanceiroPainelComLocais(List<ShiftLocation> locations) {
    if (isCompromisso) return false;
    if (temFinanceiroHabilitadoNoPainel) return true;
    if (locations.isEmpty) return false;
    final loc = matchShiftLocationForScaleEntry(this, locations);
    return loc != null && loc.financialEnabled;
  }

  static DateTime _dateOnlyLocal(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  /// Plantões/compromissos **ordinários** (sem financeiro no painel): após passar o dia civil,
  /// conta como "já tirado" na UI e nos contadores.
  ///
  /// Com financeiro no painel: usa [paid] para o dia do plantão **já passou ou é hoje** (valor
  /// recebido / confirmado). **Data futura** (mês corrente ou não) conta sempre como *a tirar*,
  /// mesmo com [paid] true — evita legado Firestore `paid` ausente → default true esconder
  /// pendências no resumo "Por vínculo".
  bool effectiveJaTiradoParaExibicaoComLocais(
      DateTime referenciaDia, List<ShiftLocation> locations) {
    final ref = _dateOnlyLocal(referenciaDia);
    final ed = _dateOnlyLocal(date);
    if (temFinanceiroPainelComLocais(locations)) {
      if (ed.isAfter(ref)) return false;
      return paid;
    }
    return paid || ed.isBefore(ref);
  }

  bool effectiveJaTiradoParaExibicao(DateTime referenciaDia) =>
      effectiveJaTiradoParaExibicaoComLocais(referenciaDia, const []);

  Color get color {
    if (colorHex == null || colorHex!.isEmpty) return const Color(0xFF2D5BFF);
    final hex = colorHex!.replaceFirst('#', '');
    if (hex.length >= 6) {
      return Color(0xFF000000 + int.parse(hex.substring(0, 6), radix: 16));
    }
    return const Color(0xFF2D5BFF);
  }

  /// Armazena data como meio-dia UTC para evitar off-by-one por timezone (ex: dia 19 virar 18).
  Map<String, dynamic> toMap() => {
        'date': Timestamp.fromDate(
            DateTime.utc(date.year, date.month, date.day, 12, 0, 0)),
        'start': start,
        'end': end,
        'dayRate': dayRate,
        'nightRate': nightRate,
        'hoursDay': hoursDay,
        'hoursNight': hoursNight,
        'totalValue': totalValue,
        'notes': notes ?? '',
        'scaleNumber': scaleNumber ?? '',
        if (numeroSei != null && numeroSei!.isNotEmpty) 'numeroSei': numeroSei,
        if (numeroOcorrencia != null && numeroOcorrencia!.isNotEmpty)
          'numeroOcorrencia': numeroOcorrencia,
        if (agendaType != null && agendaType!.isNotEmpty) 'agendaType': agendaType,
        if (isAgendaMirror) 'isAgendaMirror': true,
        if (isProdutividadeFolgaMirror) 'isProdutividadeFolgaMirror': true,
        'label': label ?? '',
        'abbreviation': abbreviation ?? '',
        'colorHex': colorHex ?? '#2D5BFF',
        'paid': paid,
        'isCompromisso': isCompromisso,
        'employerType': employerType ?? '',
        'reminder': reminder ?? '',
        'source': source ?? '',
        'lancamentoOrigem': lancamentoOrigem ?? '',
        'createdByLancamentoExpresso': createdByLancamentoExpresso,
      };

  static ScaleEntry fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    final dateTs = d['date'];
    DateTime parsed = DateTime.now();
    if (dateTs is Timestamp) {
      final dt = dateTs.toDate();
      // Normaliza para meia-noite local para evitar off-by-one por timezone
      parsed = DateTime(dt.year, dt.month, dt.day);
    }
    double parseDouble(dynamic v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v.replaceAll(',', '.')) ?? 0;
      return 0;
    }

    bool parseBool(dynamic v, {required bool fallback}) {
      if (v is bool) return v;
      if (v is num) return v != 0;
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == 'true' || s == '1' || s == 'sim' || s == 'yes') return true;
        if (s == 'false' || s == '0' || s == 'nao' || s == 'não' || s == 'no')
          return false;
      }
      return fallback;
    }

    final isMirror = parseBool(d['isAgendaMirror'], fallback: false);
    final isProdFolga =
        parseBool(d['isProdutividadeFolgaMirror'], fallback: false) ||
            doc.id.startsWith('produtividade_folga_');
    final scaleNumberRaw = (d['scaleNumber'] ?? '').toString().trim();
    ScaleEntrySeiOcorrencia? mirrorNumeros;
    if (isMirror) {
      mirrorNumeros = seiOcoFromFirestoreMap(d);
    }
    return ScaleEntry(
      id: doc.id,
      date: parsed,
      start: (d['start'] ?? '08:00').toString(),
      end: (d['end'] ?? '18:00').toString(),
      dayRate: parseDouble(d['dayRate']),
      nightRate: parseDouble(d['nightRate']),
      hoursDay: parseDouble(d['hoursDay']),
      hoursNight: parseDouble(d['hoursNight']),
      totalValue: parseDouble(d['totalValue']),
      notes: d['notes']?.toString(),
      scaleNumber: isMirror
          ? (mirrorNumeros!.sei.isNotEmpty
              ? mirrorNumeros.sei
              : (scaleNumberRaw.isEmpty ? null : scaleNumberRaw))
          : (scaleNumberRaw.isEmpty ? null : scaleNumberRaw),
      numeroSei: isMirror && mirrorNumeros!.sei.isNotEmpty
          ? mirrorNumeros.sei
          : null,
      numeroOcorrencia: isMirror && mirrorNumeros!.oco.isNotEmpty
          ? mirrorNumeros.oco
          : null,
      agendaType: (d['agendaType'] ?? '').toString().trim().isEmpty
          ? null
          : (d['agendaType'] ?? '').toString(),
      isAgendaMirror: isMirror,
      isProdutividadeFolgaMirror: isProdFolga,
      label: d['label']?.toString(),
      abbreviation: d['abbreviation']?.toString(),
      colorHex: d['colorHex']?.toString(),
      paid: parseBool(d['paid'], fallback: true),
      isCompromisso: parseBool(d['isCompromisso'], fallback: false),
      employerType: _normalizeEmployerType(d['employerType']?.toString()),
      reminder: d['reminder']?.toString(),
      reminderLeads: (d['reminderLeads'] as List<dynamic>?)
          ?.map((e) => (e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0))
          .toList(),
      notificationSoundId:
          (d['notificationSoundId'] ?? '').toString().trim().isEmpty
              ? null
              : (d['notificationSoundId'] ?? '').toString().trim(),
      notificationDeliveryMode:
          (d['notificationDeliveryMode'] ?? '').toString().trim().isEmpty
              ? null
              : (d['notificationDeliveryMode'] ?? '').toString().trim(),
      source: d['source']?.toString(),
      lancamentoOrigem: d['lancamentoOrigem']?.toString(),
      createdByLancamentoExpresso:
          parseBool(d['createdByLancamentoExpresso'], fallback: false),
    );
  }

  static String? _normalizeEmployerType(String? v) {
    if (v == null || v.isEmpty) return null;
    final s = v.toLowerCase();
    if (s == 'state' || s == 'estado') return 'state';
    if (s == 'municipality' || s == 'municipio') return 'municipality';
    if (s == 'private' || s == 'particular') return 'private';
    return null;
  }
}

/// Frente de serviço (tipo de plantão com nome e cor).
class FrenteServico {
  final String id;
  final String name;
  final String colorHex;

  const FrenteServico(
      {required this.id, required this.name, required this.colorHex});

  Color get color {
    final hex = colorHex.replaceFirst('#', '');
    if (hex.length >= 6)
      return Color(0xFF000000 + int.parse(hex.substring(0, 6), radix: 16));
    return const Color(0xFF2D5BFF);
  }

  Map<String, dynamic> toMap() => {'name': name, 'colorHex': colorHex};
}
