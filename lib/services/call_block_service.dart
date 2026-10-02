import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Estado do «Bloquear chamadas de desconhecidos» (SOMENTE ANDROID 10+).
class CallBlockStatus {
  const CallBlockStatus({
    this.platformSupported = false,
    this.sdkInt = 0,
    this.roleAvailable = false,
    this.roleHeld = false,
    this.contactsGranted = false,
    this.enabled = false,
    this.blockedCount = 0,
    this.lastBlockedAt,
  });

  /// Android (fora do Android o card nem aparece).
  final bool platformSupported;
  final int sdkInt;

  /// O aparelho oferece a triagem de chamadas (Android 10+).
  final bool roleAvailable;

  /// O WISDOMAPP é o app de triagem de chamadas.
  final bool roleHeld;
  final bool contactsGranted;

  /// Preferência do usuário (liga/desliga).
  final bool enabled;
  final int blockedCount;
  final DateTime? lastBlockedAt;

  /// Bloqueio realmente funcionando agora.
  bool get active => enabled && roleHeld && contactsGranted;

  /// Ligado, mas falta alguma permissão para funcionar.
  bool get needsPermission => enabled && (!roleHeld || !contactsGranted);

  factory CallBlockStatus.fromMap(Map<dynamic, dynamic> m) {
    final last = (m['lastBlockedAt'] as num?)?.toInt() ?? 0;
    return CallBlockStatus(
      platformSupported: true,
      sdkInt: (m['sdkInt'] as num?)?.toInt() ?? 0,
      roleAvailable: m['supported'] == true,
      roleHeld: m['roleHeld'] == true,
      contactsGranted: m['contactsGranted'] == true,
      enabled: m['enabled'] == true,
      blockedCount: (m['blockedCount'] as num?)?.toInt() ?? 0,
      lastBlockedAt:
          last > 0 ? DateTime.fromMillisecondsSinceEpoch(last) : null,
    );
  }
}

/// Preferências do bloqueio (ficam no aparelho, lidas pelo serviço nativo).
class CallBlockConfig {
  const CallBlockConfig({
    this.permitirContatos = true,
    this.silenciar = false,
    this.permitidos = const [],
    this.bloqueados = const [],
  });

  /// «Permitir contatos salvos»: quem está na agenda sempre pode ligar.
  final bool permitirContatos;

  /// «O que fazer com a chamada»: silenciar (entra sem tocar) × bloquear.
  final bool silenciar;

  /// Números que sempre podem ligar.
  final List<String> permitidos;

  /// Números sempre bloqueados (mesmo sendo contato).
  final List<String> bloqueados;

  CallBlockConfig copyWith({
    bool? permitirContatos,
    bool? silenciar,
    List<String>? permitidos,
    List<String>? bloqueados,
  }) =>
      CallBlockConfig(
        permitirContatos: permitirContatos ?? this.permitirContatos,
        silenciar: silenciar ?? this.silenciar,
        permitidos: permitidos ?? this.permitidos,
        bloqueados: bloqueados ?? this.bloqueados,
      );

  factory CallBlockConfig.fromMap(Map<dynamic, dynamic> m) {
    List<String> lista(Object? v) =>
        v is List ? v.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList() : const [];
    return CallBlockConfig(
      permitirContatos: m['allowContacts'] != false,
      silenciar: m['mode'] == 'silence',
      permitidos: lista(m['allow']),
      bloqueados: lista(m['block']),
    );
  }
}

/// Uma chamada recusada (guardada só no aparelho).
class CallBlockRegistro {
  const CallBlockRegistro({required this.numero, required this.quando});

  /// Número de quem ligou (vazio = oculto/privado).
  final String numero;
  final DateTime quando;
}

/// Ponte Dart ↔ nativo do bloqueio de chamadas de números fora dos contatos.
///
/// O Android usa um `CallScreeningService` (papel ROLE_CALL_SCREENING) que
/// recebe só o número de quem liga — sem histórico de chamadas nem
/// READ_CALL_LOG / READ_PHONE_STATE. A preferência fica no nativo
/// (SharedPreferences) para funcionar com o app fechado.
abstract final class CallBlockService {
  static const MethodChannel _ch =
      MethodChannel('br.com.wisdomapp/call_block');

  static bool get platformSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<CallBlockStatus> status() async {
    if (!platformSupported) return const CallBlockStatus();
    return _statusCall('getStatus');
  }

  static Future<CallBlockStatus> setEnabled(bool enabled) async {
    if (!platformSupported) return const CallBlockStatus();
    return _statusCall('setEnabled', {'enabled': enabled});
  }

  static Future<CallBlockStatus> resetCount() async {
    if (!platformSupported) return const CallBlockStatus();
    return _statusCall('resetCount');
  }

  /// Histórico das chamadas recusadas (mais recentes primeiro).
  static Future<List<CallBlockRegistro>> registros() async {
    if (!platformSupported) return const [];
    try {
      final r = await _ch.invokeMethod<List<dynamic>>('getLog') ?? const [];
      final lista = <CallBlockRegistro>[];
      for (final e in r) {
        if (e is! Map) continue;
        final t = (e['at'] as num?)?.toInt() ?? 0;
        if (t <= 0) continue;
        lista.add(CallBlockRegistro(
          numero: (e['number'] ?? '').toString(),
          quando: DateTime.fromMillisecondsSinceEpoch(t),
        ));
      }
      lista.sort((a, b) => b.quando.compareTo(a.quando));
      return lista;
    } on PlatformException {
      return const [];
    } on MissingPluginException {
      return const [];
    }
  }

  /// Preferências da tela «Bloqueio de chamadas».
  static Future<CallBlockConfig> config() async {
    if (!platformSupported) return const CallBlockConfig();
    return _configCall('getConfig');
  }

  static Future<CallBlockConfig> salvarConfig(CallBlockConfig c) async {
    if (!platformSupported) return c;
    return _configCall('saveConfig', {
      'allowContacts': c.permitirContatos,
      'mode': c.silenciar ? 'silence' : 'block',
      'allow': c.permitidos,
      'block': c.bloqueados,
    });
  }

  /// «Permitir» no relatório: vai para «Números permitidos» e sai da lista.
  static Future<CallBlockConfig> permitirNumero(String numero) async {
    if (!platformSupported) return const CallBlockConfig();
    return _configCall('allowNumber', {'number': numero});
  }

  /// «Adicionar aos contatos»: abre o «Novo contato» do aparelho com o
  /// número. True = virou contato (e saiu do relatório).
  static Future<bool> adicionarAosContatos(String numero) async {
    if (!platformSupported) return false;
    try {
      return await _ch.invokeMethod<bool>('addContact', {'number': numero}) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<CallBlockConfig> _configCall(String method, [Map<String, dynamic>? args]) async {
    try {
      final r = await _ch.invokeMethod<Map<dynamic, dynamic>>(method, args);
      return r == null ? const CallBlockConfig() : CallBlockConfig.fromMap(r);
    } on PlatformException {
      return const CallBlockConfig();
    } on MissingPluginException {
      return const CallBlockConfig();
    }
  }

  /// «Limpar registros»: apaga o histórico e zera o contador.
  static Future<CallBlockStatus> limparRegistros() async {
    if (!platformSupported) return const CallBlockStatus();
    return _statusCall('clearLog');
  }

  /// Abre a tela do sistema «app de identificação de chamadas e spam».
  /// Devolve true se o papel ficou concedido.
  static Future<bool> requestRole() => _boolCall('requestRole');

  static Future<bool> requestContactsPermission() =>
      _boolCall('requestContactsPermission');

  static Future<bool> openAppSettings() => _boolCall('openAppSettings');

  static Future<CallBlockStatus> _statusCall(
    String method, [
    Map<String, dynamic>? args,
  ]) async {
    try {
      final r = await _ch.invokeMethod<Map<dynamic, dynamic>>(method, args);
      if (r == null) return const CallBlockStatus(platformSupported: true);
      return CallBlockStatus.fromMap(r);
    } on PlatformException {
      return const CallBlockStatus(platformSupported: true);
    } on MissingPluginException {
      return const CallBlockStatus(platformSupported: true);
    }
  }

  static Future<bool> _boolCall(String method) async {
    if (!platformSupported) return false;
    try {
      return await _ch.invokeMethod<bool>(method) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}
