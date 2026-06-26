/// Antecedências pré-definidas (minutos + rótulo) para chips de lembrete personalizado.
/// Usado em lançamento expresso, pré-cadastro de plantões e Agenda.
const kReminderLeadChipPresets = <({int minutes, String label})>[
  (minutes: 15, label: '15 min'),
  (minutes: 30, label: '30 min'),
  (minutes: 60, label: '1 h'),
  (minutes: 120, label: '2 h'),
  (minutes: 360, label: '6 h'),
  (minutes: 1440, label: '1 dia'),
  (minutes: 2880, label: '2 dias'),
  (minutes: 10080, label: '1 semana'),
];
