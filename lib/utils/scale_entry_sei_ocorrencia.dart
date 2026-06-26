import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/field_text_limits.dart';
import '../models/scale_entry.dart';
import '../theme/app_colors.dart';

export '../constants/field_text_limits.dart'
    show
        kAudienciaRelatoMaxLength,
        kScaleNotesGridCollapsedChars,
        kScaleNotesGridExpandChars,
        kScaleNotesMaxLength,
        clampTextToMaxLength,
        normalizeAudienciaRelatoForSave,
        normalizeScaleNotesForSave;

/// SEI e RAI (ocorrência) — somente módulo Audiências/Compromissos (e espelho na Escalas).
class ScaleEntrySeiOcorrencia {
  const ScaleEntrySeiOcorrencia({required this.sei, required this.oco});

  final String sei;
  final String oco;

  bool get hasSei => sei.isNotEmpty;
  bool get hasOco => oco.isNotEmpty;
}

/// Nº do **plantão** (Escalas) — com ou sem financeiro; não é SEI nem RAI.
String scalePlantaoNumberFromEntry(ScaleEntry e) {
  if (e.isAgendaMirror) return '';
  return (e.scaleNumber ?? '').trim();
}

/// SEI/RAI no documento Firestore (espelho `agenda_*` ou leitura legada).
ScaleEntrySeiOcorrencia seiOcoFromFirestoreMap(Map<String, dynamic> d) {
  final sei = (d['numeroSei'] ?? '').toString().trim();
  final oco = (d['numeroOcorrencia'] ?? '').toString().trim();
  return ScaleEntrySeiOcorrencia(sei: sei, oco: oco);
}

/// SEI/RAI só para espelho da Agenda na lista de Escalas.
ScaleEntrySeiOcorrencia? seiOcoFromAgendaMirrorEntry(ScaleEntry e) {
  if (!e.isAgendaMirror) return null;
  var sei = (e.numeroSei ?? '').trim();
  var oco = (e.numeroOcorrencia ?? '').trim();
  if (sei.isEmpty && oco.isEmpty) {
    final sn = (e.scaleNumber ?? '').trim();
    if (sn.isNotEmpty && !sn.toUpperCase().startsWith('OCO')) {
      sei = sn;
    }
  }
  return ScaleEntrySeiOcorrencia(sei: sei, oco: oco);
}

@Deprecated('Use scalePlantaoNumberFromEntry ou seiOcoFromAgendaMirrorEntry')
ScaleEntrySeiOcorrencia seiOcoFromScaleEntry(ScaleEntry e) {
  final mirror = seiOcoFromAgendaMirrorEntry(e);
  if (mirror != null) return mirror;
  final plantao = scalePlantaoNumberFromEntry(e);
  return ScaleEntrySeiOcorrencia(sei: '', oco: plantao);
}

/// Linhas no card: plantão/compromisso (Escalas) → Nº Escala; audiência → Nº Ocorrência.
List<String> scaleEntryResumoNumberLines(ScaleEntry e) {
  if (e.isAgendaMirror) {
    final isAud =
        (e.agendaType ?? '').toString().trim().toLowerCase() == 'audiencia';
    final n = seiOcoFromAgendaMirrorEntry(e);
    if (n == null) return [];
    if (isAud) {
      return scaleEntryAudienciaResumoLines(n);
    }
    final sn = (e.scaleNumber ?? '').trim();
    if (sn.isEmpty) return const [];
    return ['🏷️ Nº Escala: $sn'];
  }
  final num = scalePlantaoNumberFromEntry(e);
  if (num.isEmpty) {
    return const [];
  }
  return ['🏷️ Nº Escala: $num'];
}

/// Mensagem quando não há número no card (Escalas).
String scaleEntryResumoNumberEmptyLabel(ScaleEntry e) {
  if (e.isAgendaMirror &&
      (e.agendaType ?? '').toString().trim().toLowerCase() == 'audiencia') {
    return 'Sem nº ocorrência';
  }
  return 'Sem nº escala';
}

/// Valores da edição rápida de **plantão** (Escalas).
class ScalePlantaoEditValues {
  const ScalePlantaoEditValues({
    required this.scaleNumber,
    required this.notes,
  });

  final String scaleNumber;
  final String notes;
}

/// Patch Firestore — plantão: só `scaleNumber` + `notes` (remove SEI/RAI se existirem).
Map<String, dynamic> scalePlantaoFirestorePatch(ScalePlantaoEditValues values) {
  final scaleNumber = values.scaleNumber.trim().toUpperCase();
  final notes = normalizeScaleNotesForSave(values.notes);

  return {
    'scaleNumber': scaleNumber.isEmpty ? FieldValue.delete() : scaleNumber,
    'notes': notes.isEmpty ? FieldValue.delete() : notes,
    'numeroSei': FieldValue.delete(),
    'numeroOcorrencia': FieldValue.delete(),
  };
}

/// Título no resumo do dia — sem repetir SEI/ocorrência no texto do título.
String scaleEntryResumoDisplayTitle(ScaleEntry e) {
  final tipo = (e.agendaType ?? '').toString().trim().toLowerCase();
  if (e.isAgendaMirror && tipo == 'audiencia') return 'Audiência';
  if (e.isAgendaMirror && tipo == 'compromisso') return 'Compromisso';
  var label = (e.label ?? 'Plantão').trim();
  if (label.isEmpty) return 'Plantão';
  final seiMatch = RegExp(r'\s*·\s*SEI\s', caseSensitive: false).firstMatch(label);
  if (seiMatch != null) {
    label = label.substring(0, seiMatch.start).trim();
  }
  final ocoMatch = RegExp(r'\s*·\s*OCO\s', caseSensitive: false).firstMatch(label);
  if (ocoMatch != null) {
    label = label.substring(0, ocoMatch.start).trim();
  }
  if (label.toUpperCase().startsWith('AUDIÊNCIA')) return 'Audiência';
  if (label.toUpperCase().startsWith('COMPROMISSO')) return 'Compromisso';
  return label;
}

/// Título com primeira letra maior (resumo Escalas).
Widget scaleEntryResumoTitleText(
  ScaleEntry e, {
  required double fontSize,
  Color color = AppColors.textPrimary,
}) {
  final title = scaleEntryResumoDisplayTitle(e);
  if (title.isEmpty) return const SizedBox.shrink();
  final first = title.substring(0, 1);
  final rest = title.length > 1 ? title.substring(1) : '';
  return RichText(
    text: TextSpan(
      style: TextStyle(
        fontSize: fontSize,
        fontWeight: FontWeight.w900,
        height: 1.25,
        color: color,
      ),
      children: [
        TextSpan(
          text: first,
          style: TextStyle(fontSize: fontSize * 1.28, fontWeight: FontWeight.w900),
        ),
        TextSpan(text: rest),
      ],
    ),
  );
}

/// Estilo destacado para data e horário no resumo do dia.
TextStyle scaleEntryResumoMetaTextStyle({
  required double fontSize,
  Color color = AppColors.deepBlue,
}) {
  return TextStyle(
    fontSize: fontSize,
    fontWeight: FontWeight.w800,
    height: 1.35,
    color: color,
    letterSpacing: 0.15,
  );
}

/// Dia da semana · data · horário (resumo Escalas).
String scaleEntryDiaSemanaDataHorario(ScaleEntry e) {
  final raw = DateFormat('EEEE', 'pt_BR').format(e.date);
  final diaSemana =
      raw.isEmpty ? raw : '${raw[0].toUpperCase()}${raw.substring(1)}';
  final data = DateFormat('dd/MM/yyyy', 'pt_BR').format(e.date);
  return '$diaSemana · $data · ${e.start}–${e.end}';
}

/// Linhas SEI / nº ocorrência (módulo Audiências).
List<String> scaleEntryAudienciaResumoLines(ScaleEntrySeiOcorrencia n) {
  final out = <String>[];
  if (n.hasSei) out.add('📂 Processo (SEI): ${n.sei}');
  if (n.hasOco) out.add('🏷️ Nº Ocorrência: ${n.oco}');
  return out;
}

@Deprecated('Use scaleEntryAudienciaResumoLines')
List<String> scaleEntrySeiOcoLines(ScaleEntrySeiOcorrencia n) {
  return scaleEntryAudienciaResumoLines(n);
}

/// Audiência / compromisso da Agenda (espelho ou legado) — edição completa, não nº escala.
bool scaleEntryUsesAgendaFullEditor(ScaleEntry e) {
  if (e.isAgendaMirror) return true;
  final id = e.id?.trim() ?? '';
  if (id.startsWith('agenda_')) return true;
  final t = (e.agendaType ?? '').trim().toLowerCase();
  if (t == 'audiencia' || t == 'compromisso') return true;
  final label = (e.label ?? '').trim().toUpperCase();
  if (label.startsWith('AUDIÊNCIA') || label.startsWith('AUDIENCIA')) {
    return true;
  }
  return false;
}

/// Plantão profissional/ordinário (com ou sem financeiro). Muitos sem financeiro
/// ficam com `isCompromisso: true` no Firestore — não são compromisso da Agenda.
bool scaleEntryIsPlantaoParaEdicaoRapida(ScaleEntry e) {
  if (e.isAgendaMirror) return false;
  final id = e.id?.trim() ?? '';
  if (id.startsWith('agenda_')) return false;

  if (!e.isCompromisso) return true;

  return scaleEntryLooksLikePlantaoProfissional(e);
}

bool scaleEntryLooksLikePlantaoProfissional(ScaleEntry e) {
  final label = (e.label ?? '').trim().toUpperCase();
  if (RegExp(
    r'PLANT[AÃ]O|ORDIN[AÁ]RIO|CASE|REFOR[CÇ]O|CPU|MOT\.|NOTURNO|DIURNO|EXTRA',
    caseSensitive: false,
  ).hasMatch(label)) {
    return true;
  }

  final et = (e.employerType ?? '').trim().toLowerCase();
  if (et == 'state' || et == 'municipality' || et == 'private') {
    return true;
  }

  final abbr = (e.abbreviation ?? '').trim().toUpperCase();
  if (abbr.length >= 2 &&
      abbr.length <= 12 &&
      RegExp(r'^[A-Z0-9]{2,12}$').hasMatch(abbr)) {
    return true;
  }

  final src = (e.source ?? '').trim().toLowerCase();
  final origem = (e.lancamentoOrigem ?? '').trim().toLowerCase();
  if (src.contains('plantao') ||
      src.contains('escala') ||
      src.contains('recorrente') ||
      origem.contains('plantao') ||
      origem.contains('escala')) {
    return true;
  }

  return false;
}

/// Compromisso particular real, audiência ou espelho Agenda — tela cheia.
bool scaleEntryRequiresFullEditor(ScaleEntry e) {
  if (scaleEntryUsesAgendaFullEditor(e)) return true;
  if (!e.isCompromisso) return false;
  return !scaleEntryIsPlantaoParaEdicaoRapida(e);
}
