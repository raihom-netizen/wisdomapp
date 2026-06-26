import 'package:cloud_firestore/cloud_firestore.dart';

/// Cor padrão sugerida para audiências (dourado metálico — "Old Gold" clássico).
/// Visual premium que destaca audiências no calendário em telas Full HD.
const String kAgendaAudienciaDefaultColor = '#D4AF37';

/// Cor padrão sugerida para compromissos da Agenda (teal).
const String kAgendaCompromissoDefaultColor = '#0D9488';

/// Tipos suportados pelo espelho.
enum AgendaMirrorType { compromisso, audiencia }

extension AgendaMirrorTypeX on AgendaMirrorType {
  String get wireValue => switch (this) {
        AgendaMirrorType.compromisso => 'compromisso',
        AgendaMirrorType.audiencia => 'audiencia',
      };

  String get label => switch (this) {
        AgendaMirrorType.compromisso => 'Compromisso (Agenda)',
        AgendaMirrorType.audiencia => 'Audiência (Agenda)',
      };
}

/// Mantém a coleção `users/{uid}/scales` sincronizada com itens criados no
/// módulo Agenda (compromissos e audiências), para que apareçam automaticamente
/// no calendário de Escalas com a cor escolhida.
///
/// Cada item da Agenda gera um doc espelho com **ID determinístico**
/// `agenda_{agendaId}` em `scales`. Marca:
///   - `isAgendaMirror: true`
///   - `agendaId`: ID do doc original em `reminders`
///   - `agendaType`: 'compromisso' | 'audiencia'
///   - `isCompromisso: true` (não impacta cálculos financeiros)
///   - `totalValue: 0` (idem)
///   - `scaleNumber`: SEI ou identificador (audiência) para o resumo em Escalas
///
/// Editar / excluir o item da Agenda atualiza / remove o espelho automaticamente.
class AgendaScaleMirrorService {
  AgendaScaleMirrorService._();

  static String _docId(String agendaId) => 'agenda_$agendaId';

  static DocumentReference<Map<String, dynamic>> _ref({
    required String userDocId,
    required String agendaId,
  }) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userDocId)
          .collection('scales')
          .doc(_docId(agendaId));

  /// Cria ou atualiza o espelho. Use ao salvar (criação ou edição) na Agenda.
  ///
  /// [date] = dia local (será gravado como meio-dia UTC, mesma regra de ScaleEntry).
  /// [startHHmm] / [endHHmm] = horário "HH:mm" (24h).
  /// [colorHex] = cor do calendário (`#RRGGBB`); se vazio usa o default do tipo.
  /// [scaleNumber] = ex.: número SEI (audiência); gravado no espelho para o resumo do dia em Escalas.
  static Future<void> upsert({
    required String userDocId,
    required String agendaId,
    required AgendaMirrorType type,
    required String label,
    required DateTime date,
    required String startHHmm,
    required String endHHmm,
    required String colorHex,
    String notes = '',
    String scaleNumber = '',
    String numeroSei = '',
    String numeroOcorrencia = '',
    bool createdByLancamentoExpresso = false,
    bool createdByMagic = false,
    String? magicBatchId,
    FieldValue? magicGeneratedAt,
    String? sourceOverride,
    String? lancamentoOrigemOverride,
  }) async {
    if (userDocId.isEmpty || agendaId.isEmpty) return;
    final fallbackColor = type == AgendaMirrorType.audiencia
        ? kAgendaAudienciaDefaultColor
        : kAgendaCompromissoDefaultColor;
    final corFinal = colorHex.trim().isEmpty ? fallbackColor : colorHex.trim();
    final dateUtcNoon =
        DateTime.utc(date.year, date.month, date.day, 12, 0, 0);
    final tipoWire = type.wireValue;
    final sei = numeroSei.trim().isNotEmpty
        ? numeroSei.trim()
        : scaleNumber.trim();
    final oco = numeroOcorrencia.trim();
    final payload = <String, dynamic>{
      'date': Timestamp.fromDate(dateUtcNoon),
      'start': startHHmm,
      'end': endHHmm,
      'label': label,
      'abbreviation': '',
      'colorHex': corFinal,
      'paid': false,
      'isCompromisso': true,
      'totalValue': 0,
      'dayRate': 0,
      'nightRate': 0,
      'hoursDay': 0,
      'hoursNight': 0,
      'employerType': 'private',
      'notes': notes,
      'scaleNumber': sei,
      if (sei.isNotEmpty) 'numeroSei': sei,
      if (oco.isNotEmpty) 'numeroOcorrencia': oco,
      'reminder': '',
      'reminderLeads': <int>[],
      'isAgendaMirror': true,
      'agendaId': agendaId,
      'agendaType': tipoWire,
      'source': sourceOverride ??
          (createdByLancamentoExpresso
              ? 'lancamento_expresso'
              : 'agenda_$tipoWire'),
      'lancamentoOrigem': lancamentoOrigemOverride ??
          (createdByLancamentoExpresso
              ? 'lancamento_expresso'
              : 'agenda_$tipoWire'),
      'createdByLancamentoExpresso': createdByLancamentoExpresso,
      'updatedAt': FieldValue.serverTimestamp(),
    };
    if (createdByMagic) {
      payload['createdByMagic'] = true;
      if (magicBatchId != null && magicBatchId.trim().isNotEmpty) {
        payload['magicBatchId'] = magicBatchId.trim();
      }
      if (magicGeneratedAt != null) {
        payload['magicGeneratedAt'] = magicGeneratedAt;
      }
    }
    try {
      await _ref(userDocId: userDocId, agendaId: agendaId).set(
        payload,
        SetOptions(merge: true),
      );
    } catch (_) {
      // Espelho é melhor-esforço — falha silenciosa não bloqueia o fluxo da Agenda.
    }
  }

  /// Remove o espelho. Use ao excluir o item da Agenda.
  static Future<void> delete({
    required String userDocId,
    required String agendaId,
  }) async {
    if (userDocId.isEmpty || agendaId.isEmpty) return;
    try {
      await _ref(userDocId: userDocId, agendaId: agendaId).delete();
    } catch (_) {
      // idem upsert — falha silenciosa.
    }
  }
}
