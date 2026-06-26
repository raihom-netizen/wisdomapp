import '../models/agenda_alert_queue_item.dart';

/// Fila após envio (push/e-mail):
/// - **0–3 dias:** aba «Notificados».
/// - **3–7 dias:** aba «Arquivadas».
/// - **>7 dias:** limpeza automática (cliente + servidor).
class AgendaAlertsArchivePolicy {
  AgendaAlertsArchivePolicy._();

  /// Dias na aba «Notificados» após o envio (antes de ir para Arquivadas).
  static const int daysUntilArchiveTab = 3;

  /// Dias totais no Firestore / fila após notificação (depois limpeza).
  static const int visibleArchivedDays = 7;

  static int daysSinceNotified(AgendaAlertQueueItem item, [DateTime? reference]) {
    final at = notifiedAt(item);
    if (at == null) return 999;
    final now = reference ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dayNotified = DateTime(at.year, at.month, at.day);
    return today.difference(dayNotified).inDays;
  }

  static DateTime archivedVisibleSince(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(const Duration(days: visibleArchivedDays));
  }

  /// Momento em que o aviso foi efetivamente notificado (push/e-mail).
  static DateTime? notifiedAt(AgendaAlertQueueItem item) {
    if (!item.isSent) return null;
    return item.sentAt ?? item.notifyAt;
  }

  /// Enviado há menos de [daysUntilArchiveTab] dias — aba «Notificados».
  static bool isRecentlyNotified(
    AgendaAlertQueueItem item, [
    DateTime? reference,
  ]) {
    if (!item.isSent || item.isCancelled) return false;
    if (notifiedAt(item) == null) return false;
    final days = daysSinceNotified(item, reference);
    return days >= 0 && days < daysUntilArchiveTab;
  }

  /// Entre [daysUntilArchiveTab] e [visibleArchivedDays] após o envio — aba «Arquivadas».
  static bool isArchivedTabVisible(
    AgendaAlertQueueItem item, [
    DateTime? reference,
  ]) {
    if (!item.isSent || item.isCancelled) return false;
    if (notifiedAt(item) == null) return false;
    final days = daysSinceNotified(item, reference);
    return days >= daysUntilArchiveTab && days < visibleArchivedDays;
  }

  /// Ainda na fila (notificados recentes ou arquivadas), até [visibleArchivedDays] dias.
  static bool isSentStillVisible(
    AgendaAlertQueueItem item, [
    DateTime? reference,
  ]) {
    return isRecentlyNotified(item, reference) ||
        isArchivedTabVisible(item, reference);
  }

  static bool isPendingStillVisible(
    AgendaAlertQueueItem item, [
    DateTime? reference,
  ]) {
    if (!item.isPending || item.isCancelled) return false;
    final now = reference ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final eventDay =
        DateTime(item.eventAt.year, item.eventAt.month, item.eventAt.day);
    return !eventDay.isBefore(today);
  }

  static bool isVisibleInQueue(
    AgendaAlertQueueItem item, [
    DateTime? reference,
  ]) {
    if (item.isCancelled) return false;
    if (item.isPending) return isPendingStillVisible(item, reference);
    if (item.isSent) return isSentStillVisible(item, reference);
    return false;
  }

  static String get retentionSummary =>
      'Notificados: visíveis $daysUntilArchiveTab dias após o envio · '
      'Arquivadas: de $daysUntilArchiveTab a $visibleArchivedDays dias · '
      'depois limpeza automática no servidor';
}
