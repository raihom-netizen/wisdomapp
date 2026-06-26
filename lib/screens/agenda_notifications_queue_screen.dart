import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/agenda_alert_queue_item.dart';
import '../utils/agenda_alerts_archive_policy.dart';
import '../services/agenda_alerts_queue_service.dart';
import '../services/agenda_server_sync_service.dart';
import '../theme/agenda_modern_ui.dart';
import '../theme/app_colors.dart';
import '../utils/firestore_user_doc_id.dart';

/// Fila de notificações (servidor): audiências, compromissos e escalas — grid premium.
class AgendaNotificationsQueueScreen extends StatefulWidget {
  const AgendaNotificationsQueueScreen({super.key});

  @override
  State<AgendaNotificationsQueueScreen> createState() =>
      _AgendaNotificationsQueueScreenState();
}

class _AgendaNotificationsQueueScreenState
    extends State<AgendaNotificationsQueueScreen> {
  AgendaQueueChannelFilter _channel = AgendaQueueChannelFilter.compromisso;
  AgendaQueueStatusFilter _statusFilter = AgendaQueueStatusFilter.pending;
  bool _syncing = false;

  String get _uid => firestoreUserDocIdForAppShell(
        FirebaseAuth.instance.currentUser?.uid ?? '',
      );

  Future<void> _syncNow() async {
    if (_uid.isEmpty || _syncing) return;
    setState(() => _syncing = true);
    try {
      final r = await AgendaServerSyncService.requestFullRebuild(_uid);
      if (mounted) {
        final msg = !r.ok
            ? (r.message ?? 'Não foi possível sincronizar agora. Tente de novo.')
            : r.didWork
                ? 'Servidor reorganizou: ${r.reminders} agenda + ${r.scales} escalas. '
                    'Push/e-mail conforme Configurações.'
                : 'Fila já estava atualizada no servidor. Push/e-mail conforme Configurações.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: r.ok ? null : AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Não foi possível sincronizar agora. Tente de novo.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      appBar: AppBar(
        title: const Text(
          'Fila de notificações',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        backgroundColor: AppColors.deepBlueDark,
        foregroundColor: Colors.white,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _InfoBanner(onSync: _syncing ? null : _syncNow, syncing: _syncing),
          if (_statusFilter == AgendaQueueStatusFilter.archived)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Material(
                color: const Color(0xFFE8F4FD),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.archive_outlined,
                        size: 20,
                        color: AppColors.primary.withValues(alpha: 0.85),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Arquivadas: entram aqui '
                          '${AgendaAlertsArchivePolicy.daysUntilArchiveTab} dias '
                          'após o envio e ficam até '
                          '${AgendaAlertsArchivePolicy.visibleArchivedDays} dias. '
                          'Depois o servidor remove — só permanecem as pendentes.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: Colors.blueGrey.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_statusFilter == AgendaQueueStatusFilter.notifiedRecent)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Material(
                color: const Color(0xFFE8F5E9),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 20,
                        color: Colors.green.shade700,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Notificados: push/e-mail já enviados — visíveis '
                          '${AgendaAlertsArchivePolicy.daysUntilArchiveTab} dias '
                          'para conferência. Depois vão para Arquivadas.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            color: Colors.green.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (_uid.isEmpty)
            const Expanded(
              child: Center(
                child: Text(
                  'Faça login para ver a fila.',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: StreamBuilder<List<AgendaAlertQueueItem>>(
                stream: AgendaAlertsQueueService.watchQueue(_uid),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting &&
                      !snap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  final all = snap.data ?? [];
                  final counts = AgendaAlertsQueueService.countsForChannel(
                    all,
                    _channel,
                  );
                  final filtered = AgendaAlertsQueueService.filter(
                    items: all,
                    channel: _channel,
                    statusFilter: _statusFilter,
                  );
                  final dayGroups =
                      AgendaAlertsQueueService.groupByEventDay(filtered);
                  final channelColor = switch (_channel) {
                    AgendaQueueChannelFilter.audiencia => AppColors.deepBlue,
                    AgendaQueueChannelFilter.compromisso => AppColors.accent,
                    AgendaQueueChannelFilter.escala => AppColors.logoOrange,
                  };

                  return CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                        child: _ChannelSelector(
                          selected: _channel,
                          all: all,
                          onSelected: (c) => setState(() => _channel = c),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                          child: SegmentedButton<AgendaQueueStatusFilter>(
                            segments: [
                              ButtonSegment(
                                value: AgendaQueueStatusFilter.pending,
                                label: Text(
                                  'Pend. (${counts.pending})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                icon: const Icon(Icons.schedule_rounded, size: 18),
                              ),
                              ButtonSegment(
                                value: AgendaQueueStatusFilter.notifiedRecent,
                                label: Text(
                                  'Notif. (${counts.notifiedRecent})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                icon: const Icon(
                                  Icons.mark_email_read_outlined,
                                  size: 18,
                                ),
                              ),
                              ButtonSegment(
                                value: AgendaQueueStatusFilter.archived,
                                label: Text(
                                  'Arq. (${counts.archived})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                                icon: const Icon(
                                  Icons.archive_outlined,
                                  size: 18,
                                ),
                              ),
                            ],
                            selected: {_statusFilter},
                            onSelectionChanged: (s) {
                              if (s.isEmpty) return;
                              setState(() => _statusFilter = s.first);
                            },
                            style: ButtonStyle(
                              minimumSize: WidgetStateProperty.all(
                                const Size(0, 48),
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                        ),
                      ),
                      if (dayGroups.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _emptyMessage(_channel, _statusFilter),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontWeight: FontWeight.w600,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        ..._buildDayGroupSlivers(
                          context,
                          dayGroups,
                          channelColor,
                          _statusFilter,
                        ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _emptyMessage(
    AgendaQueueChannelFilter ch,
    AgendaQueueStatusFilter status,
  ) {
    final tipo = switch (ch) {
      AgendaQueueChannelFilter.audiencia => 'audiências',
      AgendaQueueChannelFilter.compromisso => 'compromissos',
      AgendaQueueChannelFilter.escala => 'plantões/escalas',
    };
    return switch (status) {
      AgendaQueueStatusFilter.pending =>
        'Nenhum aviso pendente em $tipo (hoje em diante).\n'
            'Ao criar, editar data/hora no mesmo dia ou excluir, a fila atualiza sozinha.',
      AgendaQueueStatusFilter.notifiedRecent =>
        'Nenhum aviso notificado recentemente em $tipo.\n'
            'Após push/e-mail, ficam aqui por '
            '${AgendaAlertsArchivePolicy.daysUntilArchiveTab} dias.',
      AgendaQueueStatusFilter.archived =>
        'Nenhum aviso arquivado em $tipo.\n'
            'Entram aqui após '
            '${AgendaAlertsArchivePolicy.daysUntilArchiveTab} dias do envio e '
            'permanecem até ${AgendaAlertsArchivePolicy.visibleArchivedDays} dias.',
    };
  }
}

List<Widget> _buildDayGroupSlivers(
  BuildContext context,
  List<({DateTime day, List<AgendaAlertQueueItem> items})> dayGroups,
  Color channelColor,
  AgendaQueueStatusFilter statusFilter,
) {
  final w = MediaQuery.sizeOf(context).width;
  final cols = w >= 560 ? 2 : 1;
  final out = <Widget>[];

  for (var g = 0; g < dayGroups.length; g++) {
    final group = dayGroups[g];
    out.add(
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, g == 0 ? 4 : 12, 16, 8),
          child: _DaySectionHeader(
            day: group.day,
            count: group.items.length,
            accent: channelColor,
          ),
        ),
      ),
    );
    out.add(
      SliverPadding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, g == dayGroups.length - 1 ? 24 : 8),
        sliver: SliverGrid(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: cols == 1 ? 1.32 : 0.95,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => AgendaModernFadeIn(
              index: i,
              child: _AlertGridCard(
                item: group.items[i],
                showDueBadge:
                    statusFilter == AgendaQueueStatusFilter.pending,
                statusFilter: statusFilter,
              ),
            ),
            childCount: group.items.length,
          ),
        ),
      ),
    );
  }
  return out;
}

class _DaySectionHeader extends StatelessWidget {
  const _DaySectionHeader({
    required this.day,
    required this.count,
    required this.accent,
  });

  final DateTime day;
  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final d = DateTime(day.year, day.month, day.day);
    final isToday = d == today;
    final isTomorrow = d == tomorrow;

    final gradient = isToday
        ? LinearGradient(
            colors: [
              accent,
              accent.withValues(alpha: 0.65),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          )
        : isTomorrow
            ? LinearGradient(
                colors: [
                  accent.withValues(alpha: 0.35),
                  accent.withValues(alpha: 0.12),
                ],
              )
            : null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: gradient,
        color: gradient == null ? Colors.white : null,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isToday
              ? accent.withValues(alpha: 0.55)
              : const Color(0xFFE2E8F0),
          width: isToday ? 2 : 1,
        ),
        boxShadow: isToday
            ? [
                BoxShadow(
                  color: accent.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
      ),
      child: Row(
        children: [
          Icon(
            isToday
                ? Icons.today_rounded
                : isTomorrow
                    ? Icons.wb_sunny_outlined
                    : Icons.calendar_month_rounded,
            color: isToday ? Colors.white : accent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AgendaAlertsQueueService.formatDayHeader(day),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 14,
                color: isToday ? Colors.white : AppColors.deepBlueDark,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isToday
                  ? Colors.white.withValues(alpha: 0.22)
                  : accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count aviso${count == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: isToday ? Colors.white : accent,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelSelector extends StatelessWidget {
  const _ChannelSelector({
    required this.selected,
    required this.all,
    required this.onSelected,
  });

  final AgendaQueueChannelFilter selected;
  final List<AgendaAlertQueueItem> all;
  final ValueChanged<AgendaQueueChannelFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: _ChannelChip(
              label: 'Audiências',
              icon: Icons.gavel_rounded,
              color: AppColors.deepBlue,
              filter: AgendaQueueChannelFilter.audiencia,
              selected: selected,
              counts: AgendaAlertsQueueService.countsForChannel(
                all,
                AgendaQueueChannelFilter.audiencia,
              ),
              onTap: onSelected,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ChannelChip(
              label: 'Compromissos',
              icon: Icons.event_rounded,
              color: AppColors.accent,
              filter: AgendaQueueChannelFilter.compromisso,
              selected: selected,
              counts: AgendaAlertsQueueService.countsForChannel(
                all,
                AgendaQueueChannelFilter.compromisso,
              ),
              onTap: onSelected,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _ChannelChip(
              label: 'Escalas',
              icon: Icons.work_history_rounded,
              color: AppColors.logoOrange,
              filter: AgendaQueueChannelFilter.escala,
              selected: selected,
              counts: AgendaAlertsQueueService.countsForChannel(
                all,
                AgendaQueueChannelFilter.escala,
              ),
              onTap: onSelected,
            ),
          ),
        ],
      ),
    );
  }
}

class _ChannelChip extends StatelessWidget {
  const _ChannelChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.filter,
    required this.selected,
    required this.counts,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final AgendaQueueChannelFilter filter;
  final AgendaQueueChannelFilter selected;
  final ({int pending, int notifiedRecent, int archived}) counts;
  final ValueChanged<AgendaQueueChannelFilter> onTap;

  @override
  Widget build(BuildContext context) {
    final isOn = selected == filter;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onTap(filter),
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 52),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            gradient: isOn
                ? LinearGradient(
                    colors: [
                      color,
                      color.withValues(alpha: 0.72),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: isOn ? null : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isOn ? color.withValues(alpha: 0.5) : const Color(0xFFE2E8F0),
              width: isOn ? 2 : 1,
            ),
            boxShadow: isOn
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: isOn ? Colors.white : color),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                  color: isOn ? Colors.white : AppColors.deepBlueDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${counts.pending} pend.',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: isOn
                      ? Colors.white.withValues(alpha: 0.92)
                      : AppColors.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.onSync, required this.syncing});

  final VoidCallback? onSync;
  final bool syncing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.12),
            AppColors.accent.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Push e e-mail no horário agendado',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: AppColors.deepBlueDark,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AgendaAlertsQueueService.archivedRetentionHint(),
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: AppColors.primary.withValues(alpha: 0.9),
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'A fila é montada no servidor — este app só exibe, para ficar rápido. '
            'Ao criar audiência, compromisso ou plantão, o aviso entra na fila na hora. '
            'Push/e-mail saem no horário «Enviar em» (ex.: plantão 07:00 com «1 hora antes» = 06:00). '
            'Antecedências já passadas não são reenviadas.',
            style: TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onSync,
            icon: syncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync_rounded, size: 18),
            label: Text(
              syncing ? 'Reorganizando…' : 'Reorganizar fila (opcional)',
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              foregroundColor: AppColors.deepBlueDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertGridCard extends StatelessWidget {
  const _AlertGridCard({
    required this.item,
    required this.showDueBadge,
    required this.statusFilter,
  });

  final AgendaAlertQueueItem item;
  final bool showDueBadge;
  final AgendaQueueStatusFilter statusFilter;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isOverdue = item.isPending && !item.notifyAt.isAfter(now);
    final urgency = AgendaModernUI.urgencyFromNotifyAt(
      item.notifyAt,
      isSent: item.isSent,
      isPending: item.isPending,
    );
    final urgencyStyle = AgendaModernUI.styleFor(urgency);
    final channel = item.channelKind;
    final (icon, color) = switch (channel) {
      'audiencia' => (Icons.gavel_rounded, AppColors.deepBlue),
      'compromisso' => (Icons.event_rounded, AppColors.accent),
      'escala' => (Icons.work_history_rounded, AppColors.logoOrange),
      _ => (Icons.notifications_active_rounded, AppColors.primary),
    };

    final channels = <String>[];
    if (item.pushEnabled) channels.add('Push');
    if (item.emailEnabled) channels.add('E-mail');

    return Material(
      color: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: urgencyStyle.color.withValues(alpha: 0.45),
          width: 1.5,
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: BoxDecoration(
                color: urgencyStyle.color,
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: AppColors.deepBlueDark,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        AgendaAlertsQueueService.channelLabel(channel),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                ),
                AgendaUrgencyBadge(tier: urgency, compact: true),
                if (showDueBadge && isOverdue) ...[
                  const SizedBox(width: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.logoOrange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'A enviar',
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: AppColors.logoOrange,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                item.body,
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textSecondary,
                  height: 1.25,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 6),
            _miniRow(
              Icons.alarm_rounded,
              item.isPending
                  ? 'Enviar em: ${AgendaAlertsQueueService.formatDateTime(item.notifyAt)}'
                  : 'Enviado: ${AgendaAlertsQueueService.formatDateTime(item.sentAt ?? item.notifyAt)}',
            ),
            const SizedBox(height: 4),
            _miniRow(
              Icons.event_available_rounded,
              'Evento: ${AgendaAlertsQueueService.formatDateTime(item.eventAt)}',
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _tag(AgendaAlertsQueueService.leadLabel(item.leadMin)),
                if (channels.isNotEmpty) _tag(channels.join(' + ')),
                if (item.isSent && item.sentAt != null)
                  _tag(
                    switch (statusFilter) {
                      AgendaQueueStatusFilter.archived =>
                        'Arquivado · ${AgendaAlertsQueueService.formatDateTime(item.sentAt!)}',
                      _ =>
                        '✓ Notificado · ${AgendaAlertsQueueService.formatDateTime(item.sentAt!)}',
                    },
                    success: true,
                  ),
              ],
            ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: AppColors.textMuted),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _tag(String text, {bool success = false}) {
    return Container(
      constraints: const BoxConstraints(minHeight: 26),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: success
            ? AppColors.success.withValues(alpha: 0.1)
            : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: success ? AppColors.success : AppColors.textSecondary,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
