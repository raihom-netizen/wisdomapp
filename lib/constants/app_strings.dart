/// Strings centralizadas para mensagens comuns e feedback ao usuário.
class AppStrings {
  AppStrings._();

  // UX e descoberta
  static const String sheetSelectionHint =
      'Toque em "Selecionar" para marcar vários e excluir em lote.';
  static const String refreshUpdated = 'Atualizado';

  // Empty states
  static const String addFirstIncome = 'Adicionar primeira receita';
  static const String addFirstExpense = 'Adicionar primeira despesa';
  static const String noTransactionsInPeriod = 'Nenhum lançamento no período.';
  static const String addIncomeOrExpenseToStart =
      'Adicione sua primeira receita ou despesa para começar.';

  // Confirmações e ações
  static const String deleteSelected = 'Excluir selecionados?';
  static const String deleteSelectedConfirm = 'lançamento(s) serão excluídos. Esta ação não pode ser desfeita.';
  static const String cancel = 'Cancelar';
  static const String delete = 'Excluir';
  static const String select = 'Selecionar';
  static const String confirm = 'Confirmar';
  static const String confirmPayment = 'Confirmar pagamento';

  // Labels de acessibilidade
  static const String semanticsSelect = 'Botão Selecionar para marcar vários itens';
  static const String semanticsDeleteBatch = 'Excluir itens selecionados em lote';
  static const String semanticsConfirmPayment = 'Confirmar pagamento do lançamento';
  static const String semanticsUpdateNow = 'Atualizar agora e recarregar a página';

  // Offline
  static const String offlineIndicator = 'Sem conexão';
  static const String backOnline = 'Conexão restabelecida';
}
