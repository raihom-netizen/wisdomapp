import 'package:cloud_firestore/cloud_firestore.dart';

import 'agenda_notification_cutoff.dart';
import 'agenda_reminder_end_of_day.dart';
import 'agenda_reminder_notify_times.dart';
import '../services/notification_message_builder.dart';
import '../services/local_notification_preferences.dart';
import '../services/yearly_commitment_repeat_service.dart';
import 'agenda_delivery_channel_prefs.dart';

/// Canal lógico do lembrete (prioridade na fila iOS).
enum AgendaNotificationChannelKind {
  audiencia,
  compromisso,
  escala,
  financeiro,
}

int agendaNotificationPriority(AgendaNotificationChannelKind kind) =>
    switch (kind) {
      AgendaNotificationChannelKind.audiencia => 0,
      AgendaNotificationChannelKind.compromisso => 1,
      AgendaNotificationChannelKind.escala => 2,
      AgendaNotificationChannelKind.financeiro => 3,
    };

/// Um aviso local agendado (config geral ou por evento).
class AgendaNotificationPlanEntry {
  const AgendaNotificationPlanEntry({
    required this.notifyAt,
    required this.priority,
    required this.docId,
    required this.leadMinutes,
    required this.title,
    required this.body,
    required this.channelKind,
    this.eventSoundId,
    this.eventDeliveryMode,
  });

  final DateTime notifyAt;
  final int priority;
  final String docId;
  final int leadMinutes;
  final String title;
  final String body;
  final AgendaNotificationChannelKind channelKind;
  final String? eventSoundId;
  final String? eventDeliveryMode;
}

/// Preferências carregadas de `users/{uid}/settings/notifications`.
class AgendaNotificationUserSettings {
  const AgendaNotificationUserSettings({
    this.reminderEnabled = true,
    this.notifEscalas = true,
    this.notifCompromissos = true,
    this.notifAudiencias = true,
    this.notifFinanceiro = true,
    this.globalLeads = LocalNotificationPreferences.kDefaultLeads,
    this.deliveryEscala = AgendaTypeDeliveryMode.both,
    this.deliveryCompromisso = AgendaTypeDeliveryMode.both,
    this.deliveryAudiencia = AgendaTypeDeliveryMode.both,
  });

  final bool reminderEnabled;
  final bool notifEscalas;
  final bool notifCompromissos;
  /// Audiências — configuração à parte (padrão ligado).
  final bool notifAudiencias;
  final bool notifFinanceiro;

  /// Legado: ambos os tipos de agenda ativos.
  bool get notifCompromissosAudiencias => notifCompromissos && notifAudiencias;
  final List<int> globalLeads;
  final AgendaTypeDeliveryMode deliveryEscala;
  final AgendaTypeDeliveryMode deliveryCompromisso;
  final AgendaTypeDeliveryMode deliveryAudiencia;
}

AgendaNotificationUserSettings parseAgendaNotificationUserSettings(
  Map<String, dynamic>? data,
) {
  var globalLeads = List<int>.from(LocalNotificationPreferences.kDefaultLeads);
  if (data != null) {
    final raw = data['scaleReminderLeads'];
    if (raw is List && raw.isNotEmpty) {
      globalLeads = LocalNotificationPreferences.effectiveLeads(
        raw.map(
          (e) => (e is num ? e.toInt() : int.tryParse(e.toString()) ?? 0),
        ),
      );
    } else if (data['scaleReminderMinutes'] != null) {
      final m = data['scaleReminderMinutes'];
      globalLeads = [(m is int) ? m : (m is num ? m.toInt() : 60)];
    }
  }
  final legacyCompromissosAudiencias = data?['notifCompromissosAudiencias'] != false;
  final notifCompromissos = data != null && data.containsKey('notifCompromissos')
      ? data['notifCompromissos'] != false
      : legacyCompromissosAudiencias;
  final notifAudiencias = data != null && data.containsKey('notifAudiencias')
      ? data['notifAudiencias'] != false
      : true;

  return AgendaNotificationUserSettings(
    reminderEnabled: data?['scaleReminderEnabled'] != false,
    notifEscalas: data?['notifEscalas'] != false,
    notifCompromissos: notifCompromissos,
    notifAudiencias: notifAudiencias,
    notifFinanceiro: data?['notifFinanceiro'] != false,
    globalLeads: globalLeads,
    deliveryEscala: agendaTypeDeliveryModeFromFirestore(data?['deliveryEscala']),
    deliveryCompromisso:
        agendaTypeDeliveryModeFromFirestore(data?['deliveryCompromisso']),
    deliveryAudiencia:
        defaultAudienciaDeliveryFromFirestore(data?['deliveryAudiencia']),
  );
}

List<int> reminderLeadsForDoc(Map<String, dynamic> d, List<int> globalLeads) {
  // Só antecedências globais (Configurações) — sem personalizado por evento.
  final parsed = globalLeads.where((m) => m > 0).toSet().toList()..sort();
  if (parsed.isNotEmpty) return parsed;
  return List<int>.from(LocalNotificationPreferences.kDefaultLeads);
}

/// Texto premium por antecedência (iOS / Android / Web PWA — mesma regra).
typedef AgendaNotificationMessageFactory = ({String title, String body})
    Function(int leadMin);

void _appendLeads({
  required List<AgendaNotificationPlanEntry> out,
  required DateTime now,
  required DateTime eventAt,
  required List<int> leads,
  required String docId,
  required AgendaNotificationChannelKind channelKind,
  required AgendaNotificationMessageFactory messageForLead,
  DateTime? forwardCutoff,
}) {
  final floor = forwardCutoff ?? agendaNotificationScheduleFloor(now);
  if (!agendaEventEligibleForForwardNotify(eventAt, now: now)) {
    return;
  }
  final priority = agendaNotificationPriority(channelKind);
  for (final when in agendaEffectiveNotifyAtList(
    eventAt: eventAt,
    leadMinutes: leads,
    now: now,
  )) {
    if (when.isBefore(floor)) continue;
    final leadUsed = _inferLeadMinutes(eventAt, when, leads, now);
    final msg = messageForLead(leadUsed);
    out.add(
      AgendaNotificationPlanEntry(
        notifyAt: when,
        priority: priority,
        docId: docId,
        leadMinutes: leadUsed,
        title: msg.title,
        body: msg.body,
        channelKind: channelKind,
      ),
    );
  }
}

/// Antecedência (min) usada em um horário de notificação — iOS/Android/Web.
int inferAgendaNotificationLeadMinutes(
  DateTime eventAt,
  DateTime notifyAt,
  List<int> leads,
  DateTime now,
) {
  return _inferLeadMinutes(eventAt, notifyAt, leads, now);
}

int _inferLeadMinutes(
  DateTime eventAt,
  DateTime notifyAt,
  List<int> leads,
  DateTime now,
) {
  if (leads.isEmpty) {
    final inferred = eventAt.difference(notifyAt).inMinutes;
    return inferred > 0 ? inferred : 60;
  }
  for (final lead in leads) {
    final expected = eventAt.subtract(Duration(minutes: lead));
    if ((expected.difference(notifyAt).inMinutes).abs() <= 5) {
      return lead;
    }
  }
  // Fallback: lead configurado mais próximo do intervalo real (evita «1 hora» no aviso de 1 dia).
  final actual = eventAt.difference(notifyAt).inMinutes;
  if (actual <= 0) return leads.first;
  var best = leads.first;
  var bestDiff = (actual - best).abs();
  for (final lead in leads) {
    final diff = (actual - lead).abs();
    if (diff < bestDiff) {
      bestDiff = diff;
      best = lead;
    }
  }
  return best;
}

/// Monta plano unificado: reminders + scales (sem espelho agenda) + financeiro.
List<AgendaNotificationPlanEntry> buildAgendaNotificationPlan({
  required DateTime now,
  required AgendaNotificationUserSettings settings,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> reminders,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> scales,
  required List<QueryDocumentSnapshot<Map<String, dynamic>>> transactions,
  DateTime? forwardCutoff,
  bool includeFinancial = true,
  String? userDisplayName,
}) {
  final plan = <AgendaNotificationPlanEntry>[];
  if (!settings.reminderEnabled) return plan;
  final floor = forwardCutoff ?? agendaNotificationScheduleFloor(now);

  for (final doc in reminders) {
    final d = doc.data();
    if (!YearlyCommitmentRepeatService.shouldShowInAgendaList(
      d,
      docId: doc.id,
    )) {
      continue;
    }
    final dateTs = d['date'];
    if (dateTs == null) continue;
    final date = (dateTs as Timestamp).toDate();
    final timeStr = (d['time'] ?? '09:00').toString();
    final parts = timeStr.split(':');
    final hour = int.tryParse(parts.first) ?? 9;
    final minute = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final eventAt = DateTime(date.year, date.month, date.day, hour, minute);
    if (!agendaReminderEligibleForNotifySchedule(d, now)) continue;

    final isAudiencia = (d['type'] ?? 'compromisso').toString() == 'audiencia';
    if (isAudiencia && !settings.notifAudiencias) continue;
    if (!isAudiencia && !settings.notifCompromissos) continue;
    final delivery =
        isAudiencia ? settings.deliveryAudiencia : settings.deliveryCompromisso;
    if (!agendaAllowsLocalOrPushDelivery(delivery)) continue;
      _appendLeads(
        out: plan,
        now: now,
        eventAt: eventAt,
        leads: reminderLeadsForDoc(d, settings.globalLeads),
        docId: doc.id,
        channelKind: isAudiencia
            ? AgendaNotificationChannelKind.audiencia
            : AgendaNotificationChannelKind.compromisso,
        messageForLead: (leadMin) => NotificationMessageBuilder.fromReminderDoc(
          d,
          userName: userDisplayName,
          eventAt: eventAt,
          leadMin: leadMin,
        ),
        forwardCutoff: floor,
      );
  }

  for (final doc in scales) {
    final d = doc.data();
    if (d['isAgendaMirror'] == true) continue;
    if (d['isProdutividadeFolgaMirror'] == true) continue;
    final isCompromisso = (d['isCompromisso'] ?? false) as bool;
    if (isCompromisso && !settings.notifCompromissos) continue;
    if (!isCompromisso && !settings.notifEscalas) continue;

    final delivery = isCompromisso
        ? settings.deliveryCompromisso
        : settings.deliveryEscala;
    if (!agendaAllowsLocalOrPushDelivery(delivery)) continue;

    final date = (d['date'] as Timestamp?)?.toDate();
    final startStr = d['start'] as String?;
    if (date == null || startStr == null) continue;
    final startParts = startStr.split(':');
    final hour = int.tryParse(startParts.first) ?? 8;
    final minute =
        startParts.length > 1 ? (int.tryParse(startParts[1]) ?? 0) : 0;
    final eventAt =
        DateTime(date.year, date.month, date.day, hour, minute);
    if (!agendaEventEligibleForForwardNotify(eventAt, now: now)) {
      continue;
    }

    _appendLeads(
      out: plan,
      now: now,
      eventAt: eventAt,
      leads: reminderLeadsForDoc(d, settings.globalLeads),
      docId: doc.id,
      channelKind: isCompromisso
          ? AgendaNotificationChannelKind.compromisso
          : AgendaNotificationChannelKind.escala,
      messageForLead: (leadMin) =>
          NotificationMessageBuilder.buildScaleNotificationMessage(
        d,
        userName: userDisplayName,
        eventAt: eventAt,
        leadMin: leadMin,
      ),
      forwardCutoff: floor,
    );
  }

  if (includeFinancial && settings.notifFinanceiro) {
    for (final doc in transactions) {
      final d = doc.data();
      final isIncome = (d['type'] ?? 'expense').toString() == 'income';
      if ((d['status'] ?? 'paid').toString() == 'paid') continue;
      final dateTs = d['date'];
      if (dateTs == null) continue;
      final dueDate = (dateTs as Timestamp).toDate();
      final eventAt =
          DateTime(dueDate.year, dueDate.month, dueDate.day, 9, 0);
      if (!eventAt.isAfter(now)) continue;
      final desc =
          (d['description'] ?? d['category'] ?? (isIncome ? 'Receita' : 'Despesa'))
              .toString();
      final amount = (d['amount'] ?? 0).toDouble();
      _appendLeads(
        out: plan,
        now: now,
        eventAt: eventAt,
        leads: settings.globalLeads,
        docId: doc.id,
        channelKind: AgendaNotificationChannelKind.financeiro,
        messageForLead: (_) => isIncome
            ? NotificationMessageBuilder.buildContaReceberNotification(
                desc: desc,
                valor: amount.toStringAsFixed(2),
                userName: userDisplayName,
              )
            : NotificationMessageBuilder.buildContaPagarNotification(
                desc: desc,
                valor: amount.toStringAsFixed(2),
                userName: userDisplayName,
              ),
      );
    }
  }

  plan.sort((a, b) {
    final t = a.notifyAt.compareTo(b.notifyAt);
    if (t != 0) return t;
    return a.priority.compareTo(b.priority);
  });
  return plan;
}

/// iOS: no máximo **um** aviso local por evento (`docId`) — o mais próximo no tempo.
///
/// Assim os ~60 slots do SO cobrem até ~60 **eventos** distintos (audiência,
/// compromisso, plantão), em vez de ~30 eventos com 2 antecedências cada.
/// Todos os leads continuam no servidor (push/e-mail via `agendaAlerts`).
List<AgendaNotificationPlanEntry> compactAgendaPlanForIosLocalSlots(
  List<AgendaNotificationPlanEntry> plan,
) {
  if (plan.isEmpty) return plan;
  final bestByDoc = <String, AgendaNotificationPlanEntry>{};
  for (final e in plan) {
    final prev = bestByDoc[e.docId];
    if (prev == null || e.notifyAt.isBefore(prev.notifyAt)) {
      bestByDoc[e.docId] = e;
    }
  }
  final out = bestByDoc.values.toList();
  out.sort((a, b) {
    final t = a.notifyAt.compareTo(b.notifyAt);
    if (t != 0) return t;
    return a.priority.compareTo(b.priority);
  });
  return out;
}

/// ID estável por doc + minuto do aviso (evita colisão entre escala/reminder).
int stableAgendaNotificationId(String docId, DateTime notifyAt) {
  final bucket = notifyAt.millisecondsSinceEpoch ~/ 60000;
  final h = Object.hash(docId, bucket);
  return 100000 + (h.abs() % 800000);
}
