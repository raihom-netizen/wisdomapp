import 'package:shared_preferences/shared_preferences.dart';

/// Último JSON do widget nativo (Android/iOS) — funciona sem internet.
class WidgetNativePayloadCache {
  WidgetNativePayloadCache._();

  static const _kUid = 'widget_native_payload_uid_v1';
  static const _kJson = 'widget_native_payload_json_v1';

  static String? _memoryUid;
  static String? _memoryJson;

  static Future<void> warmUp() async {
    final prefs = await SharedPreferences.getInstance();
    _memoryUid = (prefs.getString(_kUid) ?? '').trim();
    if (_memoryUid == null || _memoryUid!.isEmpty) {
      _memoryUid = null;
      _memoryJson = null;
      return;
    }
    _memoryJson = prefs.getString(_kJson);
  }

  static String? peekJson(String uid) {
    final clean = uid.trim();
    if (clean.isEmpty || _memoryUid != clean) return null;
    final j = _memoryJson;
    if (j == null || j.isEmpty) return null;
    return j;
  }

  static Future<void> save(String uid, String jsonStr) async {
    final clean = uid.trim();
    if (clean.isEmpty || jsonStr.isEmpty) return;
    _memoryUid = clean;
    _memoryJson = jsonStr;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kUid, clean);
    await prefs.setString(_kJson, jsonStr);
  }

  static Future<void> clear() async {
    _memoryUid = null;
    _memoryJson = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kUid);
    await prefs.remove(_kJson);
  }
}
