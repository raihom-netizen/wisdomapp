import 'package:flutter/foundation.dart';

import '../models/weekly_summary_ui_data.dart';

/// Mensagem flutuante global (resumo semanal, promo, push em primeiro plano) — aparece no [HomeShell] sobre qualquer módulo.
enum InAppFloatingKind { weeklySummary, pushOrPromo }

class InAppFloatingPayload {
  final String id;
  final InAppFloatingKind kind;
  final String title;
  final String body;
  final String? openUrl;
  final Future<void> Function()? onDismissPersist;
  /// Resumo semanal estruturado (diálogo premium com cartões).
  final WeeklySummaryUiData? weeklyStructured;
  /// Rótulo do botão no cartão flutuante (ex.: OK para resumo semanal).
  final String bannerActionLabel;

  InAppFloatingPayload({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    this.openUrl,
    this.onDismissPersist,
    this.weeklyStructured,
    this.bannerActionLabel = 'Ver depois',
  });
}

class InAppFloatingMessageService {
  InAppFloatingMessageService._();

  static final ValueNotifier<InAppFloatingPayload?> notifier =
      ValueNotifier<InAppFloatingPayload?>(null);

  static void show(InAppFloatingPayload payload) {
    notifier.value = payload;
  }

  /// Push/promo em primeiro plano: não substitui o resumo semanal até o utilizador tocar em OK.
  static bool tryShowPushPromo(InAppFloatingPayload payload) {
    final cur = notifier.value;
    if (cur != null && cur.kind == InAppFloatingKind.weeklySummary) {
      return false;
    }
    notifier.value = payload;
    return true;
  }

  /// Remove o banner atual sem persistir (ex.: utilizador desativou o resumo nas definições).
  static void clearWithoutPersist() {
    notifier.value = null;
  }

  static Future<void> dismissCurrent() async {
    final cur = notifier.value;
    if (cur == null) return;
    final persist = cur.onDismissPersist;
    notifier.value = null;
    if (persist != null) {
      try {
        await persist();
      } catch (_) {}
    }
  }
}
