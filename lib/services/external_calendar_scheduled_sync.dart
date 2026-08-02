import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import 'external_calendar_bidirectional_sync.dart';

/// Sync automática Google/Apple Calendar **2× ao dia**: meia-noite (00:00) e meio-dia (12:00).
///
/// - Com o app aberto: Timer agenda o próximo horário.
/// - No boot / resume: recupera o slot devido se ainda não rodou (app fechado na hora).
/// - Só age se Google e/ou Apple estiver ativado (ver BidirectionalSync).
class ExternalCalendarScheduledSync {
  ExternalCalendarScheduledSync._();

  static const _prefsKeyPrefix = 'ext_cal_auto_slot_v1_';

  static String? _activeUid;
  static Timer? _timer;
  static Future<void>? _inFlight;

  /// Id do slot mais recente que já deveria ter rodado até [now] (local).
  /// Formato: `yyyy-MM-dd-00` (meia-noite) ou `yyyy-MM-dd-12` (meio-dia).
  static String lastDueSlotId(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    if (now.hour >= 12) {
      return '$y-$m-$d-12';
    }
    return '$y-$m-$d-00';
  }

  /// Próximo disparo após [now]: hoje 12:00 se ainda não passou; senão amanhã 00:00.
  static DateTime nextSlotAt(DateTime now) {
    final noon = DateTime(now.year, now.month, now.day, 12);
    if (now.isBefore(noon)) return noon;
    final tomorrowMidnight =
        DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    return tomorrowMidnight;
  }

  /// Boot / login: catch-up do slot devido + agenda próximo Timer.
  static Future<void> ensureStarted(String uid) async {
    if (uid.isEmpty) return;
    _activeUid = uid;
    await runCatchUpIfNeeded(uid);
    _scheduleNextTimer(uid);
  }

  /// Resume do app: só catch-up (Timer já reprograma se necessário).
  static Future<void> onAppResumed(String uid) async {
    if (uid.isEmpty) return;
    _activeUid = uid;
    await runCatchUpIfNeeded(uid);
    _scheduleNextTimer(uid);
  }

  /// Se o último slot (00h ou 12h) ainda não foi sincronizado para este uid, roda agora.
  static Future<bool> runCatchUpIfNeeded(String uid) async {
    if (uid.isEmpty) return false;
    if (_inFlight != null) {
      await _inFlight;
      return false;
    }
    var didRun = false;
    _inFlight = () async {
      didRun = await _catchUp(uid);
    }().whenComplete(() => _inFlight = null);
    await _inFlight;
    return didRun;
  }

  static Future<bool> _catchUp(String uid) async {
    final slot = lastDueSlotId(DateTime.now());
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefsKeyPrefix$uid';
      if (prefs.getString(key) == slot) return false;

      debugPrint('ExternalCalendarScheduledSync: catch-up slot $slot');
      await ExternalCalendarBidirectionalSync.runNow(uid);
      await prefs.setString(key, slot);
      return true;
    } catch (e, st) {
      debugPrint('ExternalCalendarScheduledSync catch-up: $e\n$st');
      return false;
    }
  }

  static void _scheduleNextTimer(String uid) {
    _timer?.cancel();
    final now = DateTime.now();
    final next = nextSlotAt(now);
    var wait = next.difference(now);
    if (wait < const Duration(seconds: 2)) {
      wait = const Duration(seconds: 2);
    }
    debugPrint(
      'ExternalCalendarScheduledSync: próximo sync em '
      '${wait.inMinutes} min (${next.toIso8601String()})',
    );
    _timer = Timer(wait, () {
      unawaited(_onTimerFired(uid));
    });
  }

  static Future<void> _onTimerFired(String uid) async {
    if (_activeUid != uid) return;
    try {
      final now = DateTime.now();
      final slot = lastDueSlotId(now);
      final prefs = await SharedPreferences.getInstance();
      final key = '$_prefsKeyPrefix$uid';
      if (prefs.getString(key) != slot) {
        debugPrint('ExternalCalendarScheduledSync: timer slot $slot');
        await ExternalCalendarBidirectionalSync.runNow(uid);
        await prefs.setString(key, slot);
      }
    } catch (e, st) {
      debugPrint('ExternalCalendarScheduledSync timer: $e\n$st');
    } finally {
      if (_activeUid == uid) {
        _scheduleNextTimer(uid);
      }
    }
  }

  static void stop() {
    _timer?.cancel();
    _timer = null;
    _activeUid = null;
  }
}
