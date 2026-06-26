import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../utils/agenda_notification_cutoff.dart';
import '../utils/agenda_reminder_end_of_day.dart';
import 'scale_notifications_service.dart';

/// Reagenda todas as notificações locais (plantões, audiências/compromissos da
/// Agenda e contas a pagar pendentes) para os próximos 60 dias num único passo.
///
/// **Por quê:** o BUG anterior — audiências cadastradas no módulo
/// «Audiências/Compromissos» não disparavam notificação — vinha do fato de o
/// reagendamento só rodar no `initState` do shell. Ao salvar/editar/excluir uma
/// audiência o app não reagendava, então a notificação só aparecia no próximo
/// abrir do app. Plantões/compromissos do painel expresso funcionavam porque o
/// próprio `scales_screen` chamava `scheduleFromScales` ao salvar.
///
/// Agora só estes pontos devem chamar [refresh]:
/// - criar/editar/excluir audiência, compromisso ou escala (data/hora);
/// - alterar antecedências em Configurações → Notificações;
/// - boot do app ([AgendaBootOrchestrator], 1× por sessão).
///
/// **Não** chamar em listeners Firestore (snapshots), auto-close em loop nem
/// ao marcar plantão pago — isso travava o app parado numa tela.
class AgendaNotificationsRefresher {
  AgendaNotificationsRefresher._();

  /// Janela padrão de reagendamento — mesma usada no boot do shell.
  static const Duration _kWindow = Duration(days: 60);

  /// Limite por coleção — evita ler centenas de docs desnecessários no boot.
  static const int _kMaxDocsPerCollection = 600;

  /// Evita reagendar em rajada se o usuário salvar vários itens em sequência.
  static DateTime? _lastRunAt;
  static Future<void>? _inFlight;

  /// Reagenda escalas + reminders (audiências/compromissos da Agenda) + contas
  /// pendentes para [uid].
  ///
  /// Se já houve um refresh há menos de [coalesceWithin] segundos (padrão 2s),
  /// agenda o próximo logo após o atual terminar — evita disparar GETs em
  /// rajada quando o usuário salva vários itens seguidos.
  static Future<void> refresh({
    required String uid,
    Duration coalesceWithin = const Duration(seconds: 45),
  }) {
    if (uid.isEmpty) return Future<void>.value();

    if (_inFlight != null) {
      // Já tem um refresh em andamento — espera ele terminar e devolve.
      return _inFlight!;
    }

    final last = _lastRunAt;
    if (last != null && DateTime.now().difference(last) < coalesceWithin) {
      // Coalesce: agenda um único próximo refresh ao final do delay.
      _inFlight = Future<void>.delayed(coalesceWithin, () => _doRefresh(uid));
    } else {
      _inFlight = _doRefresh(uid);
    }
    final running = _inFlight!.whenComplete(() {
      _inFlight = null;
      _lastRunAt = DateTime.now();
    });
    return running;
  }

  static Future<void> _doRefresh(String uid) async {
    try {
      await ScaleNotificationsService().init();
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      // Inclui ontem/anteanterior: audiências «em aberto» 24h após o horário.
      final remindersQueryFrom =
          startOfToday.subtract(const Duration(days: 2));
      final endOfRange = startOfToday.add(_kWindow);
      final endOfRangeDate = DateTime(
        endOfRange.year,
        endOfRange.month,
        endOfRange.day,
        23,
        59,
        59,
      );

      List<QueryDocumentSnapshot<Map<String, dynamic>>> remindersList = [];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> scalesList = [];
      String? userDisplayName;
      try {
        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        final n = (userSnap.data()?['name'] ?? '').toString().trim();
        if (n.isNotEmpty) userDisplayName = n;
      } catch (_) {}

      try {
        final remindersSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('reminders')
            .where('date',
                isGreaterThanOrEqualTo: Timestamp.fromDate(remindersQueryFrom))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfRangeDate))
            .orderBy('date')
            .limit(_kMaxDocsPerCollection)
            .get();
        remindersList = remindersSnap.docs
            .where((d) => agendaReminderEligibleForNotifySchedule(d.data(), now))
            .toList();
      } catch (_) {}

      try {
        final scalesSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('scales')
            .where('date',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfRangeDate))
            .orderBy('date')
            .limit(_kMaxDocsPerCollection)
            .get();
        scalesList = scalesSnap.docs;
      } catch (_) {}

      // Contas a pagar/receber pendentes (lembrete antes do vencimento).
      List<QueryDocumentSnapshot<Map<String, dynamic>>> transactionsList = [];
      try {
        final txSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('transactions')
            .where('status', isEqualTo: 'pending')
            .where('date',
                isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfRangeDate))
            .orderBy('date')
            .limit(_kMaxDocsPerCollection)
            .get();
        transactionsList = txSnap.docs;
      } catch (_) {}

      // Foco: audiências, compromissos, escalas e financeiro (contas a pagar/receber).
      await ScaleNotificationsService().scheduleAgendaBatch(
        uid: uid,
        reminders: remindersList,
        scales: scalesList,
        transactions: transactionsList,
        forwardCutoff: agendaNotificationScheduleFloor(now),
        userDisplayName: userDisplayName,
      );
      ScaleNotificationsService().checkDueNow();
    } catch (_) {
      // Reagendamento é melhor-esforço: jamais quebra o fluxo de save/edit.
    }
  }
}
