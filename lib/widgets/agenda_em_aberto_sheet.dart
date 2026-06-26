import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/user_profile.dart';
import '../theme/app_colors.dart';
import '../services/yearly_commitment_repeat_service.dart';
import '../utils/agenda_reminder_end_of_day.dart';
import '../utils/agenda_reminder_module_scope.dart';
import 'agenda_period_filter_bar.dart';

/// Filtro da lista «em aberto» ao abrir a partir do painel resumo.
enum AgendaAbertoFilter {
  todos,
  apenasCompromissos,
  apenasAudiencias,
}

/// Sheet estilo Início: lista em aberto com cartões premium; [buildTile] injeta edição/exclusão do ecrã pai.
Future<void> showAgendaEmAbertoSheet(
  BuildContext context, {
  required String userFsId,
  required UserProfile profile,
  AgendaAbertoFilter filter = AgendaAbertoFilter.todos,
  required Widget Function(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    bool isAudiencia,
  ) buildTile,
  VoidCallback? onVerTudoNaAgenda,
  String initialPeriod = AgendaPeriodKeys.anual,
  DateTime? initialCustomStart,
  DateTime? initialCustomEnd,
  bool hidePeriodFilter = false,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _AgendaEmAbertoSheetBody(
      userFsId: userFsId,
      profile: profile,
      filter: filter,
      buildTile: buildTile,
      onVerTudoNaAgenda: onVerTudoNaAgenda,
      initialPeriod: initialPeriod,
      initialCustomStart: initialCustomStart,
      initialCustomEnd: initialCustomEnd,
      hidePeriodFilter: hidePeriodFilter,
    ),
  );
}

class _AgendaEmAbertoSheetBody extends StatefulWidget {
  final String userFsId;
  final UserProfile profile;
  final AgendaAbertoFilter filter;
  final Widget Function(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    bool isAudiencia,
  ) buildTile;
  final VoidCallback? onVerTudoNaAgenda;
  final String initialPeriod;
  final DateTime? initialCustomStart;
  final DateTime? initialCustomEnd;
  final bool hidePeriodFilter;

  const _AgendaEmAbertoSheetBody({
    required this.userFsId,
    required this.profile,
    required this.filter,
    required this.buildTile,
    this.onVerTudoNaAgenda,
    required this.initialPeriod,
    this.initialCustomStart,
    this.initialCustomEnd,
    this.hidePeriodFilter = false,
  });

  @override
  State<_AgendaEmAbertoSheetBody> createState() => _AgendaEmAbertoSheetBodyState();
}

class _AgendaEmAbertoSheetBodyState extends State<_AgendaEmAbertoSheetBody> {
  late AgendaPeriodFilterValue _periodValue;
  Timer? _autoCloseDebounce;
  final Set<String> _autoCloseInFlight = {};

  @override
  void dispose() {
    _autoCloseDebounce?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _periodValue = agendaPeriodFilterValue(
      period: widget.initialPeriod,
      customStart: widget.initialCustomStart,
      customEnd: widget.initialCustomEnd,
    );
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _remindersStream() {
    final queryStart =
        _periodValue.rangeStart.subtract(const Duration(days: 3));
    final queryEnd = _periodValue.rangeEnd.add(const Duration(days: 1));
    return FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userFsId)
        .collection('reminders')
        .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(queryStart))
        .where('date', isLessThanOrEqualTo: Timestamp.fromDate(queryEnd))
        .limit(500)
        .snapshots();
  }

  void _scheduleAutoCloseFromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
    CollectionReference<Map<String, dynamic>> remindersRef,
  ) {
    final now = DateTime.now();
    final toClose = <String>[];
    for (final d in snap.docs) {
      if (agendaShouldAutoCloseNow(d.data(), now)) {
        toClose.add(d.id);
      }
    }
    if (toClose.isEmpty) return;
    _autoCloseDebounce?.cancel();
    _autoCloseDebounce = Timer(const Duration(milliseconds: 600), () async {
      if (!mounted) return;
      final batch = <String>[];
      for (final id in toClose) {
        if (_autoCloseInFlight.add(id)) batch.add(id);
      }
      if (batch.isEmpty) return;
      try {
        for (final id in batch) {
          await remindersRef.doc(id).update({
            'done': true,
            'status': 'REALIZADO',
          }).catchError((_) {});
        }
      } finally {
        for (final id in batch) {
          _autoCloseInFlight.remove(id);
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant _AgendaEmAbertoSheetBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialPeriod != widget.initialPeriod ||
        oldWidget.initialCustomStart != widget.initialCustomStart ||
        oldWidget.initialCustomEnd != widget.initialCustomEnd) {
      _periodValue = agendaPeriodFilterValue(
        period: widget.initialPeriod,
        customStart: widget.initialCustomStart,
        customEnd: widget.initialCustomEnd,
      );
    }
  }

  String get _title {
    return switch (widget.filter) {
      AgendaAbertoFilter.todos => 'Audiências e Compromissos em aberto',
      AgendaAbertoFilter.apenasCompromissos => 'Compromissos em aberto',
      AgendaAbertoFilter.apenasAudiencias => 'Audiências em aberto',
    };
  }

  @override
  Widget build(BuildContext context) {
    final remindersRef = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.userFsId)
        .collection('reminders');

    return DraggableScrollableSheet(
      initialChildSize: widget.filter == AgendaAbertoFilter.todos ? 0.72 : 0.65,
      minChildSize: 0.36,
      maxChildSize: 0.94,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
              child: Row(
                children: [
                  Material(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(ctx).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back_rounded,
                          color: AppColors.primary,
                          size: 22,
                          semanticLabel: 'Voltar',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: TextButton.styleFrom(
                      minimumSize: const Size(44, 44),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                      foregroundColor: AppColors.primary,
                    ),
                    child: const Text(
                      'Voltar',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  const Spacer(),
                  Material(
                    color: Colors.grey.shade100,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Navigator.of(ctx).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.close_rounded,
                          size: 22,
                          color: Color(0xFF1A237E),
                          semanticLabel: 'Fechar',
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 12, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.event_available_rounded,
                      color: AppColors.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1A237E),
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.onVerTudoNaAgenda != null)
                    TextButton(
                      onPressed: () {
                        Navigator.pop(ctx);
                        widget.onVerTudoNaAgenda!();
                      },
                      child: const Text(
                        'Abrir\nAudiências/Compromissos',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          height: 1.15,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!widget.hidePeriodFilter)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: AgendaPeriodFilterBar(
                  dense: true,
                  initialPeriod: widget.initialPeriod,
                  initialCustomStart: widget.initialCustomStart,
                  initialCustomEnd: widget.initialCustomEnd,
                  onChanged: (v) => setState(() => _periodValue = v),
                ),
              ),
            if (!widget.hidePeriodFilter)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _periodValue.label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textMuted.withValues(alpha: 0.9),
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _remindersStream(),
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Não foi possível carregar a agenda. Verifique a conexão.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    );
                  }
                  _scheduleAutoCloseFromSnapshot(snap.data!, remindersRef);
                  final now = DateTime.now();
                  final docs = snap.data!.docs;
                  final compromissos =
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  final audiencias =
                      <QueryDocumentSnapshot<Map<String, dynamic>>>[];
                  for (final d in docs) {
                    final data = d.data();
                    if (!YearlyCommitmentRepeatService.shouldShowInAgendaList(
                      data,
                      docId: d.id,
                    )) {
                      continue;
                    }
                    if (!agendaReminderBelongsInAgendaModule(data)) continue;
                    if (!agendaStillCountedAsOpenOnPanel(data, now)) continue;
                    if (!agendaReminderDayInRange(
                      data,
                      _periodValue.rangeStart,
                      _periodValue.rangeEnd,
                    )) {
                      continue;
                    }
                    if ((data['type'] ?? 'compromisso').toString() == 'audiencia') {
                      audiencias.add(d);
                    } else {
                      compromissos.add(d);
                    }
                  }
                  compromissos.sort((a, b) {
                    final da = agendaReminderDateTime(a.data());
                    final db = agendaReminderDateTime(b.data());
                    if (da == null || db == null) return 0;
                    return da.compareTo(db);
                  });
                  audiencias.sort((a, b) {
                    final da = agendaReminderDateTime(a.data());
                    final db = agendaReminderDateTime(b.data());
                    if (da == null || db == null) return 0;
                    return da.compareTo(db);
                  });

                  final showComp = widget.filter == AgendaAbertoFilter.todos ||
                      widget.filter == AgendaAbertoFilter.apenasCompromissos;
                  final showAud = widget.filter == AgendaAbertoFilter.todos ||
                      widget.filter == AgendaAbertoFilter.apenasAudiencias;

                  if ((!showComp || compromissos.isEmpty) &&
                      (!showAud || audiencias.isEmpty)) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_available_rounded,
                                size: 56, color: Colors.grey.shade300),
                            const SizedBox(height: 16),
                            Text(
                              switch (widget.filter) {
                                AgendaAbertoFilter.apenasCompromissos =>
                                  'Nenhum compromisso em aberto neste período',
                                AgendaAbertoFilter.apenasAudiencias =>
                                  'Nenhuma audiência em aberto neste período',
                                _ =>
                                  'Nenhuma audiência ou compromisso em aberto neste período',
                              },
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.grey.shade700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _periodValue.label,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                    children: [
                      if (showAud && audiencias.isNotEmpty) ...[
                        if (widget.filter == AgendaAbertoFilter.todos)
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 8),
                            child: Row(
                              children: [
                                const Icon(Icons.gavel_rounded,
                                    size: 20, color: Color(0xFF1A237E)),
                                const SizedBox(width: 8),
                                Text(
                                  'Audiências (${audiencias.length})',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1A237E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ...audiencias.map((doc) => widget.buildTile(ctx, doc, true)),
                        if (widget.filter == AgendaAbertoFilter.todos &&
                            showComp &&
                            compromissos.isNotEmpty)
                          const SizedBox(height: 16),
                      ],
                      if (showComp && compromissos.isNotEmpty) ...[
                        if (widget.filter == AgendaAbertoFilter.todos)
                          Padding(
                            padding: const EdgeInsets.only(left: 4, bottom: 8),
                            child: Row(
                              children: [
                                Icon(Icons.person_outline_rounded,
                                    size: 20, color: AppColors.primary),
                                const SizedBox(width: 8),
                                Text(
                                  'Compromissos (${compromissos.length})',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF1A237E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ...compromissos.map((doc) => widget.buildTile(ctx, doc, false)),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
