import 'dart:async';

import 'agenda_notifications_refresher.dart';
import 'agenda_server_sync_service.dart';
import 'google_calendar_sync_service.dart';

/// Boot de notificações **leve no cliente**: servidor monta a fila; app só
/// reagenda lembretes locais (quando aberto) uma vez por sessão.
class AgendaBootOrchestrator {
  AgendaBootOrchestrator._();

  static String? _lastUid;
  static DateTime? _lastRunAt;
  static Future<void>? _inFlight;
  static const Duration _kMinInterval = Duration(minutes: 10);

  static Future<void> runOnLogin(String uid) {
    if (uid.isEmpty) return Future<void>.value();

    if (_inFlight != null) return _inFlight!;

    final now = DateTime.now();
    if (_lastUid == uid &&
        _lastRunAt != null &&
        now.difference(_lastRunAt!) < _kMinInterval) {
      return Future<void>.value();
    }

    _inFlight = _run(uid).whenComplete(() {
      _inFlight = null;
      _lastUid = uid;
      _lastRunAt = DateTime.now();
    });
    return _inFlight!;
  }

  static Future<void> _run(String uid) async {
    unawaited(AgendaServerSyncService.requestLoginSync(uid));
    unawaited(GoogleCalendarSyncService.warmUpIfEnabled(uid));
    await AgendaNotificationsRefresher.refresh(
      uid: uid,
      coalesceWithin: const Duration(seconds: 30),
    );
  }
}
