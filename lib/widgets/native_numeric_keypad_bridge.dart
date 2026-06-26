import 'package:flutter/services.dart';

/// Eventos do teclado nativo Android → várias instâncias via [instanceId].
class NativeNumericKeypadBridge {
  NativeNumericKeypadBridge._();

  static const MethodChannel _channel =
      MethodChannel('controletotal/native_numeric_keypad');

  static bool _hooked = false;
  static final Map<int, void Function(Map<String, dynamic>)> _byInstance = {};

  static void register(
    int instanceId,
    void Function(Map<String, dynamic>) onEvent,
  ) {
    _ensureHook();
    _byInstance[instanceId] = onEvent;
  }

  static void unregister(int instanceId) {
    _byInstance.remove(instanceId);
  }

  static void _ensureHook() {
    if (_hooked) return;
    _hooked = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'event') return;
      final raw = call.arguments;
      if (raw is! Map) return;
      final map = Map<String, dynamic>.from(raw);
      final id = map['instanceId'];
      if (id is! int) return;
      _byInstance[id]?.call(map);
    });
  }
}
