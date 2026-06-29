///
/// **Mobile (< 600dp):** só o módulo ativo fica montado (libera streams/Firestore).
/// **Tablet/desktop:** [IndexedStack] com LRU máximo 2 (atual + anterior).
abstract final class ShellLazyModulePolicy {
  ShellLazyModulePolicy._();

  static const int kMaxRetainedMaterializedModules = 2;

  /// Rodapé mobile — atalhos que o utilizador alterna com frequência.
  static const Set<int> mobileFooterIndices = {0, 1, 2, 3, 7};

  /// Módulos mais pesados (fora do rodapé) — não pré-montar no arranque.
  static const Set<int> heavyModuleIndices = {1, 3, 6, 7, 8};

  static bool preferSingleActiveModule({
    required double shortestSideDp,
    double mobileBreakpoint = 600,
  }) =>
      shortestSideDp < mobileBreakpoint;

  static void evictStaleModuleIndices({
    required Set<int> materialized,
    required int activeIndex,
    required int previousIndex,
    required bool singleActiveModule,
  }) {
    if (singleActiveModule) {
      materialized.removeWhere((idx) => idx != activeIndex);
      materialized.add(activeIndex);
      return;
    }
    final keep = {activeIndex, previousIndex};
    materialized.removeWhere((idx) => !keep.contains(idx));
    materialized.add(activeIndex);
  }
}
