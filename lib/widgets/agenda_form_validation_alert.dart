import 'package:flutter/material.dart';

import 'form_validation_alert.dart';

/// Verifica título do compromisso. Exibe alerta moderno se faltar algo.
Future<bool> validateCompromissoFormOrShowAlert(
  BuildContext context, {
  required String title,
  required bool repeatYearlyConflict,
}) async {
  final missing = collectCompromissoFormMissingFields(
    title: title,
    repeatYearlyConflict: repeatYearlyConflict,
  );
  if (missing.isEmpty) return true;
  await showFormMissingFieldsAlert(
    context,
    missing: missing,
    headline: 'Complete para salvar',
    body: 'Preencha os itens abaixo antes de gravar o compromisso:',
  );
  return false;
}

List<FormMissingField> collectCompromissoFormMissingFields({
  required String title,
  required bool repeatYearlyConflict,
}) {
  final missing = <FormMissingField>[];

  if (title.trim().isEmpty) {
    missing.add(
      const FormMissingField(
        label: 'Título',
        hint: 'Informe o nome do compromisso (ex.: Reunião, Consulta)',
        icon: Icons.event_rounded,
        colors: [Color(0xFF0D9488), Color(0xFF0F766E)],
      ),
    );
  }

  if (repeatYearlyConflict) {
    missing.add(
      const FormMissingField(
        label: 'Repetição anual',
        hint:
            'Repetir todo ano só funciona com um único dia. Desmarque dias extras ou desative a repetição.',
        icon: Icons.event_repeat_rounded,
        colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
      ),
    );
  }

  return missing;
}

/// Verifica campos obrigatórios da audiência (SEI, escala, relato, data/horário).
Future<bool> validateAudienciaFormOrShowAlert(
  BuildContext context, {
  required String numeroSei,
  required String numeroOcorrencia,
  required String resumoRelato,
}) async {
  final missing = collectAudienciaFormMissingFields(
    numeroSei: numeroSei,
    numeroOcorrencia: numeroOcorrencia,
    resumoRelato: resumoRelato,
  );
  if (missing.isEmpty) return true;
  await showFormMissingFieldsAlert(
    context,
    missing: missing,
    headline: 'Complete para salvar',
    body:
        'Preencha os campos obrigatórios da audiência. Link, local e anexo são opcionais.',
  );
  return false;
}

List<FormMissingField> collectAudienciaFormMissingFields({
  required String numeroSei,
  required String numeroOcorrencia,
  required String resumoRelato,
}) {
  final missing = <FormMissingField>[];

  if (numeroSei.trim().isEmpty) {
    missing.add(
      const FormMissingField(
        label: 'Número SEI',
        hint: 'Informe o número do processo SEI',
        icon: Icons.tag_rounded,
        colors: [Color(0xFF1A237E), Color(0xFF283593)],
      ),
    );
  }

  if (numeroOcorrencia.trim().isEmpty) {
    missing.add(
      const FormMissingField(
        label: 'Nº da escala / ocorrência',
        hint: 'Informe o número da escala ou da ocorrência',
        icon: Icons.format_list_numbered_rounded,
        colors: [Color(0xFFD4AF37), Color(0xFFB8860B)],
      ),
    );
  }

  if (resumoRelato.trim().isEmpty) {
    missing.add(
      const FormMissingField(
        label: 'Resumo / relato',
        hint: 'Descreva o assunto ou relato da audiência',
        icon: Icons.description_rounded,
        colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)],
      ),
    );
  }

  return missing;
}
