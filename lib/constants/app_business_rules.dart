/// Regras de negócio e constantes centralizadas.
class AppBusinessRules {
  AppBusinessRules._();

  /// Timeout de inatividade (minutos) para exigir biometria novamente após
  /// voltar do background. Definido propositalmente em ~1 ano (525600 min)
  /// para que o usuário **fique logado até clicar Sair** explicitamente —
  /// sem retrabalho de digital toda vez que troca de app. A primeira
  /// abertura ainda exige biometria (se ativada). Pioneirismo off→on:
  /// uma vez logado, segue logado mesmo offline e os lançamentos são
  /// gravados localmente (Firestore offline-first) e sincronizados em
  /// background quando voltar a internet.
  static const int inactivityTimeoutMinutes = 525600;

  /// Meses à frente nas listas de pendentes (receitas/despesas fixas) quando ainda não há preferência guardada.
  static const int pendingMonthsAheadDefault = 1;

  /// Limite máximo de parcelas para lançamentos parcelados (importação/cartão).
  static const int maxInstallments = 120;

  /// Máximo de parcelas em despesa/receita fixa (ex.: financiamento 360 meses).
  static const int maxFixedFlowInstallments = 360;

  /// Debounce (ms) no campo de busca do módulo financeiro.
  static const int searchDebounceMs = 300;

  /// Fatura cartão (novidade v49.57+): só entra lançamento com data de previsão >= este dia (calendário).
  /// Lançamentos antigos no cartão ficam fora da fatura em aberto.
  static DateTime faturaCartaoDataMinima = DateTime(2026, 6, 16);

  /// Visitas mínimas antes de mostrar prompt de instalar PWA.
  static const int pwaInstallPromptMinVisits = 2;
}
