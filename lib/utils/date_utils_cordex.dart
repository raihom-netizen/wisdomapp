/// Helpers "Cordex" para datas — compatibilidade Safari/iPhone.
/// O iPhone falha com new Date("2026-02-21") em alguns contextos; este helper corrige.
class DateUtilsCordex {
  /// Converte string ISO (ex: "2026-02-21" ou "2026-02-21T10:00:00") em DateTime.
  /// Tenta com traços; se falhar, usa barras (compatibilidade Safari/iPhone).
  static DateTime parseDateSafe(String? dataStr) {
    if (dataStr == null || dataStr.trim().isEmpty) return DateTime.now();
    final s = dataStr.trim();
    var dt = DateTime.tryParse(s);
    if (dt != null) return dt;
    dt = DateTime.tryParse(s.replaceAll('-', '/'));
    return dt ?? DateTime.now();
  }
}
