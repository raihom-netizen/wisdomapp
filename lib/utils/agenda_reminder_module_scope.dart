import '../models/scale_entry.dart';
import 'scale_entry_sei_ocorrencia.dart';

/// Compromissos particulares reais vs plantão da Escalas (sem financeiro) espelhado em `reminders`.
///
/// O módulo **Audiências/Compromissos** e o card do painel Início listam só:
/// - audiências;
/// - compromissos particulares (dentista, reunião, etc.).
///
/// Plantões (com ou sem financeiro) ficam **somente** em Escalas.
bool agendaReminderBelongsInAgendaModule(Map<String, dynamic> data) {
  final type = (data['type'] ?? 'compromisso').toString().trim().toLowerCase();
  if (type == 'audiencia') return true;

  final kind =
      (data['agendaKind'] ?? data['agendaModule'] ?? '').toString().trim();
  if (kind == 'compromisso_particular') return true;
  if (kind == 'plantao_escala' || data['isPlantaoEscala'] == true) {
    return false;
  }

  return !reminderDataLooksLikePlantaoEscala(data);
}

bool reminderDataLooksLikePlantaoEscala(Map<String, dynamic> data) {
  final title = (data['title'] ?? data['label'] ?? '').toString().trim();
  if (title.isEmpty) return false;

  final fake = ScaleEntry(
    date: DateTime.now(),
    start: (data['time'] ?? data['start'] ?? '08:00').toString(),
    end: (data['endTime'] ?? data['end'] ?? '18:00').toString(),
    label: title,
    isCompromisso: true,
    employerType: (data['employerType'] ?? '').toString().trim().isEmpty
        ? null
        : (data['employerType'] ?? '').toString(),
    source: (data['source'] ?? '').toString(),
    abbreviation: (data['abbreviation'] ?? '').toString(),
    createdByLancamentoExpresso: data['createdByLancamentoExpresso'] == true,
  );
  return scaleEntryLooksLikePlantaoProfissional(fake);
}

/// Título do lançamento expresso: sem financeiro mas é plantão → só Escalas.
bool expressTitleLooksLikePlantaoEscala(String title) {
  final t = title.trim();
  if (t.isEmpty) return false;
  return reminderDataLooksLikePlantaoEscala({'title': t});
}
