// Limites de texto — iguais em Web, Android e iOS (fonte única).

/// Observações de plantão / escala (Firestore `notes`).
const int kScaleNotesMaxLength = 1000;

/// Resumo relato de audiência (Firestore `resumoRelato`).
const int kAudienciaRelatoMaxLength = 2000;

/// Prévia colapsada na grid Escalas.
const int kScaleNotesGridCollapsedChars = 80;

/// «Veja mais» na grid Escalas.
const int kScaleNotesGridExpandChars = 200;

String clampTextToMaxLength(String text, int maxLen) {
  if (maxLen <= 0 || text.length <= maxLen) return text;
  return text.substring(0, maxLen);
}

/// Gravação Firestore — plantão/escala (maiúsculas, até [kScaleNotesMaxLength]).
String normalizeScaleNotesForSave(String raw) {
  final upper = raw.trim().toUpperCase();
  return clampTextToMaxLength(upper, kScaleNotesMaxLength);
}

/// Gravação Firestore — relato audiência (preserva caixa, até [kAudienciaRelatoMaxLength]).
String normalizeAudienciaRelatoForSave(String raw) {
  return clampTextToMaxLength(raw.trim(), kAudienciaRelatoMaxLength);
}
