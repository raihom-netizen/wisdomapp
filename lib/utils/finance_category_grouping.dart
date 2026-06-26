/// Agrupa totais por categoria ignorando diferença **apenas** de maiúsculas/minúsculas.
/// O primeiro rótulo visto para cada chave normalizada prevalece na UI e nos gráficos.
class FinanceCategoryMerger {
  final Map<String, String> _canonicalByNorm = {};

  void addAmount(
    Map<String, double> totals,
    String rawCategory,
    double amount, {
    String emptyLabel = 'Sem categoria',
  }) {
    final raw = rawCategory.trim();
    if (raw.isEmpty) {
      totals[emptyLabel] = (totals[emptyLabel] ?? 0) + amount;
      return;
    }
    final norm = raw.toLowerCase();
    final label = _canonicalByNorm.putIfAbsent(norm, () => raw);
    totals[label] = (totals[label] ?? 0) + amount;
  }

  /// Mesma regra de agrupamento para filtro de lista / exportação.
  static bool sameCategoryGroup(
    String rawDocCategory,
    String filterLabel, {
    String emptyLabel = 'Sem categoria',
  }) {
    final a = rawDocCategory.trim();
    final b = filterLabel.trim();
    if (a.isEmpty && b.isEmpty) return true;
    if (a.isEmpty) return b == emptyLabel || b.isEmpty;
    if (b.isEmpty) return a == emptyLabel || a.isEmpty;
    return a.toLowerCase() == b.toLowerCase();
  }
}
