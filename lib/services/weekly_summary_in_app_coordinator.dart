import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/weekly_summary_ui_data.dart';
import 'in_app_floating_message_service.dart';

/// Segunda-feira 00:00 (local) da semana que contém [d].
DateTime mondayOfWeek(DateTime d) {
  final local = DateTime(d.year, d.month, d.day);
  return local.subtract(Duration(days: local.weekday - DateTime.monday));
}

String weekKeyFromDate(DateTime d) {
  final m = mondayOfWeek(d);
  return '${m.year}-${m.month.toString().padLeft(2, '0')}-${m.day.toString().padLeft(2, '0')}';
}

/// Texto longo legado (ex.: notificações) — delega ao modelo estruturado.
Future<String> buildWeeklySummaryBody(String uid) async {
  final s = await WeeklySummaryUiData.build(uid);
  return '${s.bannerTeaser} ${s.receitasRecebidasValor} recebidas · ${s.despesasPagasValor} despesas pagas.';
}

class WeeklySummaryInAppCoordinator {
  WeeklySummaryInAppCoordinator._();

  static String? _lastScheduledId;
  static bool _building = false;

  /// Reage a alterações em `users/{uid}/settings/weekly_summary`.
  /// Por defeito **desligado** — só mostra se o utilizador ativar em Configurações (`enabled: true`).
  static Future<void> onWeeklySummarySnapshot(
    String uid,
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) async {
    final data = snap.data() ?? <String, dynamic>{};
    final enabled = data['enabled'] == true;
    if (!enabled) {
      final cur = InAppFloatingMessageService.notifier.value;
      if (cur?.kind == InAppFloatingKind.weeklySummary) {
        InAppFloatingMessageService.clearWithoutPersist();
      }
      _lastScheduledId = null;
      return;
    }

    final wk = weekKeyFromDate(DateTime.now());
    final dismissed = (data['lastFloatingDismissedWeekKey'] ?? '').toString().trim();
    if (dismissed == wk) {
      final cur = InAppFloatingMessageService.notifier.value;
      if (cur?.kind == InAppFloatingKind.weeklySummary && cur?.id == 'weekly_$wk') {
        InAppFloatingMessageService.clearWithoutPersist();
      }
      _lastScheduledId = null;
      return;
    }

    final id = 'weekly_$wk';
    if (_lastScheduledId == id && InAppFloatingMessageService.notifier.value?.id == id) {
      return;
    }
    if (_building) return;
    _building = true;
    try {
      final structured = await WeeklySummaryUiData.build(uid);
      _lastScheduledId = id;
      final ref = snap.reference;
      InAppFloatingMessageService.show(
        InAppFloatingPayload(
          id: id,
          kind: InAppFloatingKind.weeklySummary,
          title: 'Resumo semanal',
          body: structured.bannerTeaser,
          weeklyStructured: structured,
          bannerActionLabel: 'OK',
          onDismissPersist: () => ref.set(
            {
              'lastFloatingDismissedWeekKey': wk,
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          ),
        ),
      );
    } catch (_) {
      _lastScheduledId = null;
    } finally {
      _building = false;
    }
  }

  static void clearBecauseDisabled() {
    final cur = InAppFloatingMessageService.notifier.value;
    if (cur?.kind == InAppFloatingKind.weeklySummary) {
      InAppFloatingMessageService.clearWithoutPersist();
    }
    _lastScheduledId = null;
  }
}
