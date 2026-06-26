/// Sincronização Open Finance (Pluggy) agendada no servidor — alinhado a `pluggyScheduledItemsSync` (Cloud Functions).
class PluggySyncSchedule {
  PluggySyncSchedule._();

  /// Horários em que o backend dispara PATCH /items (America/Sao_Paulo).
  static const String slotsLabelBr = '12:00 e 23:00 (horário de Brasília)';

  static String get shortUserMessage =>
      'As compras e movimentos do banco entram no app após a sincronização agendada ($slotsLabelBr). '
      'O banco e a Pluggy podem levar alguns minutos para concluir.';

  static const String connectFlowNotice =
      'Depois de conectar, os lançamentos serão buscados automaticamente em '
      '12:00 e 23:00 (horário de Brasília). Não é necessário atualizar à mão: '
      'isso ajuda a manter o custo de API previsível.';

  /// Duas janelas de sincronização por dia civil (PATCH /items no servidor).
  static const int scheduledSyncRunsPerDay = 2;

  /// Texto curto para vitrine/pós-compra: ritmo incluído no pacote vs custo de API.
  static String get includedSyncsPerDayLine =>
      'Incluso no pacote: $scheduledSyncRunsPerDay atualizações automáticas por dia '
      '($slotsLabelBr), para equilibrar custos de API.';
}
