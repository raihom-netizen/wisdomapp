import 'package:flutter/foundation.dart' show debugPrint;

import 'apple_calendar_sync_service.dart';
import 'google_calendar_sync_service.dart';

/// Resultado agregado da sync Google + Apple.
class ExternalCalendarSyncResult {
  const ExternalCalendarSyncResult({
    this.googlePushed = 0,
    this.googlePulled = 0,
    this.applePulled = 0,
    this.googleRemoved = 0,
    this.appleRemoved = 0,
    this.skipped = false,
  });

  final int googlePushed;
  final int googlePulled;
  final int applePulled;

  /// Compromissos do app removidos porque o evento foi apagado no Google/Apple.
  final int googleRemoved;
  final int appleRemoved;
  final bool skipped;

  int get totalRemoved => googleRemoved + appleRemoved;

  int get totalPulled => googlePulled + applePulled;
  int get totalPushed => googlePushed;

  bool get hadChanges => totalPulled > 0 || totalPushed > 0 || totalRemoved > 0;
}

/// Orquestra sync WisdomApp ↔ Google / Apple Calendar.
///
/// - App → calendário: hooks ao criar/editar.
/// - Calendário → app: importa novos do Google; Apple só atualiza overlay.
///
/// Chamado no agendamento 00h/12h, catch-up e no botão «Sync».
class ExternalCalendarBidirectionalSync {
  ExternalCalendarBidirectionalSync._();

  static String? _lastUid;
  static DateTime? _lastRunAt;
  static Future<ExternalCalendarSyncResult>? _inFlight;

  static const Duration autoMinInterval = Duration(seconds: 45);

  /// Janela: mês civil atual em diante.
  static const int monthsBack = 0;
  static const int monthsForward = 3;

  static Future<ExternalCalendarSyncResult> runIfDue(String userDocId) {
    return _run(userDocId, force: false);
  }

  static Future<ExternalCalendarSyncResult> runNow(String userDocId) {
    return _run(userDocId, force: true);
  }

  static Future<ExternalCalendarSyncResult> _run(
    String userDocId, {
    required bool force,
  }) async {
    if (userDocId.isEmpty) {
      return const ExternalCalendarSyncResult(skipped: true);
    }

    if (_inFlight != null) return _inFlight!;

    final now = DateTime.now();
    if (!force &&
        _lastUid == userDocId &&
        _lastRunAt != null &&
        now.difference(_lastRunAt!) < autoMinInterval) {
      return const ExternalCalendarSyncResult(skipped: true);
    }

    _inFlight = _execute(userDocId).whenComplete(() {
      _inFlight = null;
      _lastUid = userDocId;
      _lastRunAt = DateTime.now();
    });
    return _inFlight!;
  }

  static Future<ExternalCalendarSyncResult> _execute(String userDocId) async {
    var gPush = 0, gPull = 0, aPull = 0, gRem = 0, aRem = 0;
    final hoje = DateTime.now();
    final janelaIni = DateTime(hoje.year, hoje.month - monthsBack, 1);
    final janelaFim =
        DateTime(hoje.year, hoje.month + monthsForward + 1, 0, 23, 59, 59);

    try {
      if (await GoogleCalendarSyncService.isEnabled(userDocId)) {
        final g = await GoogleCalendarSyncService.syncBidirectionalNow(
          userDocId: userDocId,
          monthsBack: monthsBack,
          monthsForward: monthsForward,
        );
        gPush = g.pushed;
        gPull = g.pulled;
        // Integração total: apagou no Google → sai do app.
        gRem = await GoogleCalendarSyncService.removeLocalForDeletedGoogleEvents(
          userDocId: userDocId,
          from: janelaIni,
          to: janelaFim,
        );
      }
    } catch (e, st) {
      debugPrint('ExternalCalendarBidirectionalSync Google: $e\n$st');
    }

    try {
      if (AppleCalendarSyncService.isPlatformSupported &&
          await AppleCalendarSyncService.isEnabled(userDocId)) {
        await AppleCalendarSyncService.warmUpIfEnabled(userDocId);
        final now = DateTime.now();
        var count = 0;
        for (var i = -monthsBack; i <= monthsForward; i++) {
          final month = DateTime(now.year, now.month + i, 1);
          final events = await AppleCalendarSyncService.fetchEventsForMonth(
            month,
            userDocId: userDocId,
          );
          count += events.length;
        }
        aPull = count;
        // Integração total: apagou no iPhone → sai do app.
        aRem = await AppleCalendarSyncService.removeLocalForDeletedAppleEvents(
          userDocId: userDocId,
          from: janelaIni,
          to: janelaFim,
        );
      }
    } catch (e, st) {
      debugPrint('ExternalCalendarBidirectionalSync Apple: $e\n$st');
    }

    return ExternalCalendarSyncResult(
      googlePushed: gPush,
      googlePulled: gPull,
      applePulled: aPull,
      googleRemoved: gRem,
      appleRemoved: aRem,
    );
  }
}
