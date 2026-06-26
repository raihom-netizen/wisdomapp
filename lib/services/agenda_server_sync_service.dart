import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';

/// Sincronização da fila `agendaAlerts` **no servidor** — o app não lê centenas
/// de reminders/scales nem grava lotes no Firestore (mantém o cliente rápido).
class AgendaServerSyncService {
  AgendaServerSyncService._();

  static String? _lastUid;
  static DateTime? _lastLoginSyncAt;
  static Future<AgendaServerSyncResult?>? _inFlight;
  static const Duration _kMinLoginInterval = Duration(minutes: 10);

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'us-central1');

  /// Boot / login: uma chamada leve ao servidor (máx. 1× a cada 10 min).
  static Future<AgendaServerSyncResult?> requestLoginSync(String uid) {
    if (uid.isEmpty) return Future.value(null);

    final now = DateTime.now();
    if (_lastUid == uid &&
        _lastLoginSyncAt != null &&
        now.difference(_lastLoginSyncAt!) < _kMinLoginInterval) {
      return Future.value(null);
    }

    return _call(uid: uid, full: false, markLogin: true);
  }

  /// Botão «Reorganizar fila» — força rebuild completo no servidor.
  static Future<AgendaServerSyncResult> requestFullRebuild(String uid) async {
    if (uid.isEmpty) {
      return const AgendaServerSyncResult(ok: false, message: 'Usuário não logado.');
    }
    final r = await _call(uid: uid, full: true, markLogin: false);
    return r ?? const AgendaServerSyncResult(ok: false);
  }

  static Future<AgendaServerSyncResult?> _call({
    required String uid,
    required bool full,
    required bool markLogin,
  }) {
    if (_inFlight != null) return _inFlight!;

    _inFlight = _doCall(uid: uid, full: full, markLogin: markLogin)
        .whenComplete(() => _inFlight = null);
    return _inFlight!;
  }

  static Future<AgendaServerSyncResult?> _doCall({
    required String uid,
    required bool full,
    required bool markLogin,
  }) async {
    try {
      final res = await _fn.httpsCallable('ctResyncUserAgendaAlerts').call({
        'full': full,
        'targetUid': uid,
      });
      final data = res.data;
      if (data is! Map) {
        return const AgendaServerSyncResult(ok: true);
      }
      final map = Map<String, dynamic>.from(data);
      if (markLogin) {
        _lastUid = uid;
        _lastLoginSyncAt = DateTime.now();
      }
      // Catch-up imediato: dispara alertas vencidos (push/e-mail) após montar fila.
      // Não bloqueia login/boot — roda em background.
      unawaited(() async {
        try {
          await _fn.httpsCallable('ctProcessMyDueAgendaAlerts').call({
            'targetUid': uid,
          });
        } catch (_) {}
      }());
      return AgendaServerSyncResult(
        ok: map['ok'] == true,
        skipped: map['skipped'] == true,
        reminders: (map['reminders'] as num?)?.toInt() ?? 0,
        scales: (map['scales'] as num?)?.toInt() ?? 0,
      );
    } on FirebaseFunctionsException catch (e) {
      return AgendaServerSyncResult(
        ok: false,
        message: e.message ?? 'Erro ao sincronizar no servidor.',
      );
    } catch (_) {
      return const AgendaServerSyncResult(
        ok: false,
        message: 'Não foi possível contactar o servidor.',
      );
    }
  }
}

class AgendaServerSyncResult {
  const AgendaServerSyncResult({
    required this.ok,
    this.skipped = false,
    this.reminders = 0,
    this.scales = 0,
    this.message,
  });

  final bool ok;
  final bool skipped;
  final int reminders;
  final int scales;
  final String? message;

  int get total => reminders + scales;
  bool get didWork => !skipped && total > 0;
}
