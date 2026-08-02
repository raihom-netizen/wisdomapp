import 'package:shared_preferences/shared_preferences.dart';

/// Última sincronização bem-sucedida do widget (horário local do aparelho).
class WidgetLastSyncPrefs {
  WidgetLastSyncPrefs._();

  static const _kMs = 'widget_last_sync_ms_v1';

  static int? _memoryMs;

  static Future<void> warmUp() async {
    final prefs = await SharedPreferences.getInstance();
    _memoryMs = prefs.getInt(_kMs);
  }

  static int? lastSyncMsSync() => _memoryMs;

  static Future<int?> loadLastSyncMs() async {
    if (_memoryMs != null) return _memoryMs;
    final prefs = await SharedPreferences.getInstance();
    _memoryMs = prefs.getInt(_kMs);
    return _memoryMs;
  }

  static Future<void> saveNow([DateTime? when]) async {
    final ms = (when ?? DateTime.now()).millisecondsSinceEpoch;
    _memoryMs = ms;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kMs, ms);
  }
}
