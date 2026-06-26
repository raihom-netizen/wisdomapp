import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../constants/currency_formats.dart';
import '../models/scale_rates_period.dart';
import '../services/scale_rates_period_service.dart';
import '../theme/app_colors.dart';
import 'admin_scale_rates_period_editor_page.dart';

/// Painel Admin — histórico de períodos AC4 GO, agendamento e sincronização Firestore.
class AdminScaleRatesPeriodsPanel extends StatefulWidget {
  const AdminScaleRatesPeriodsPanel({
    super.key,
    required this.brandBlue,
    required this.brandTeal,
  });

  final Color brandBlue;
  final Color brandTeal;

  @override
  State<AdminScaleRatesPeriodsPanel> createState() =>
      _AdminScaleRatesPeriodsPanelState();
}

class _AdminScaleRatesPeriodsPanelState
    extends State<AdminScaleRatesPeriodsPanel> {
  bool _syncing = false;
  bool _recalculating = false;

  Future<void> _recalcAllUsers({bool force = true, bool silent = false}) async {
    setState(() => _recalculating = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('ctRecalcGoiasScaleRatesAllUsers')
          .call<Map<String, dynamic>>({'force': force});
      final data = res.data;
      if (mounted && !silent) {
        final users = data['users'] ?? 0;
        final updated = data['updatedScales'] ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Recálculo concluído: $updated plantão(ões) em $users usuário(s).',
            ),
          ),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro no recálculo: ${e.message}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro no recálculo: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _recalculating = false);
    }
  }

  Future<void> _syncBootstrap() async {
    setState(() => _syncing = true);
    try {
      await ScaleRatesPeriodService().seedBootstrapIfEmpty();
      await _recalcAllUsers(force: true, silent: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Histórico sincronizado e plantões recalculados para todos os usuários.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao sincronizar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _openPeriodEditor({
    ScaleRatesPeriod? existing,
    bool isLegacySeed = false,
  }) async {
    final period = await Navigator.of(context).push<ScaleRatesPeriod>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AdminScaleRatesPeriodEditorPage(
          existing: existing,
          isLegacySeed: isLegacySeed,
          brandBlue: widget.brandBlue,
          brandTeal: widget.brandTeal,
        ),
      ),
    );
    if (period == null || !mounted) return;

    try {
      await ScaleRatesPeriodService().addOrUpdatePeriod(period);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              period.effectiveFrom.isAfter(DateTime.now())
                  ? 'Período agendado para ${DateFormat('dd/MM/yyyy HH:mm').format(period.effectiveFrom)}.'
                  : 'Período salvo e em vigor para novos cálculos.',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao salvar: $e')),
        );
      }
    }
  }

  String _statusLabel(ScaleRatesPeriod p, List<ScaleRatesPeriod> all) {
    final now = DateTime.now();
    if (p.effectiveFrom.isAfter(now)) return 'Agendado';
    if (p.isActiveAt(now, all)) return 'Vigente';
    return 'Histórico';
  }

  ({Color bg, Color fg, Color accent, IconData icon}) _statusTheme(String status) {
    switch (status) {
      case 'Vigente':
        return (
          bg: const Color(0xFFDCFCE7),
          fg: const Color(0xFF166534),
          accent: const Color(0xFF22C55E),
          icon: Icons.check_circle_rounded,
        );
      case 'Agendado':
        return (
          bg: const Color(0xFFFFEDD5),
          fg: const Color(0xFF9A3412),
          accent: AppColors.logoOrange,
          icon: Icons.schedule_rounded,
        );
      default:
        return (
          bg: const Color(0xFFE2E8F0),
          fg: const Color(0xFF475569),
          accent: const Color(0xFF64748B),
          icon: Icons.history_rounded,
        );
    }
  }

  String _formatUntil(DateTime? until) {
    if (until == null) return 'Sem fim definido';
    return DateFormat('dd/MM/yyyy HH:mm').format(until);
  }

  Widget _timelineStrip(List<ScaleRatesPeriod> sorted) {
    if (sorted.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.brandBlue.withValues(alpha: 0.06),
            widget.brandTeal.withValues(alpha: 0.08),
            AppColors.logoOrange.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: widget.brandTeal.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Linha do tempo — 2 tabelas',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 12),
          ...sorted.asMap().entries.map((entry) {
            final i = entry.key;
            final p = entry.value;
            final theme = _statusTheme(_statusLabel(p, sorted));
            final until = p.effectiveUntil(sorted);
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: theme.accent,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(theme.icon, color: Colors.white, size: 16),
                    ),
                    if (i < sorted.length - 1)
                      Container(
                        width: 3,
                        height: 36,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [theme.accent, sorted.length > i + 1
                                ? _statusTheme(_statusLabel(sorted[i + 1], sorted)).accent
                                : theme.accent],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: i < sorted.length - 1 ? 12 : 0),
                    child: Text(
                      '${p.label}\n'
                      '${DateFormat('dd/MM/yyyy HH:mm').format(p.effectiveFrom)}'
                      ' → ${_formatUntil(until)}',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                        color: theme.fg,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ScaleRatesPeriod>>(
      stream: ScaleRatesPeriodService().watchPeriods(),
      builder: (context, snap) {
        final periods = snap.data ?? ScaleRatesPeriodRegistry.bootstrapPeriods();
        final sorted = ScaleRatesPeriod.sortAsc(periods);
        final active = ScaleRatesPeriod.resolveAt(DateTime.now(), sorted);
        final scheduled =
            sorted.where((p) => p.effectiveFrom.isAfter(DateTime.now())).toList();
        final hasLegacy = sorted.any((p) => p.id == 'ac4_jun2024');
        final hasJuly = sorted.any(
          (p) => p.id == ScaleRatesPeriodRegistry.july2026PeriodId,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    widget.brandBlue,
                    widget.brandTeal,
                    AppColors.deepBlue.withValues(alpha: 0.9),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: widget.brandBlue.withValues(alpha: 0.35),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.timeline_rounded,
                            color: Colors.white, size: 26),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Banco de Horas GO — Tabelas por período',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Mantenha 2 períodos: tabela atual + reajuste agendado. '
                    'Cálculos retroativos respeitam cada data/hora do serviço.',
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Colors.white.withValues(alpha: 0.92),
                    ),
                  ),
                  if (active != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Vigente: ${active.label} • desde '
                        '${DateFormat('dd/MM/yyyy HH:mm').format(active.effectiveFrom)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                  if (scheduled.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '${scheduled.length} reajuste(s) agendado(s)',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.logoOrange.withValues(alpha: 0.95),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      if (!hasLegacy)
                        FilledButton.icon(
                          onPressed: () => _openPeriodEditor(isLegacySeed: true),
                          icon: const Icon(Icons.foundation_rounded),
                          label: const Text('Criar período base'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: widget.brandBlue,
                          ),
                        ),
                      FilledButton.icon(
                        onPressed: () => _openPeriodEditor(),
                        icon: const Icon(Icons.add_rounded),
                        label: Text(hasJuly ? 'Novo reajuste' : 'Agendar reajuste'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.logoOrange,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _syncing ? null : _syncBootstrap,
                        icon: _syncing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.cloud_sync_rounded),
                        label: const Text('Sincronizar'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            _recalculating ? null : () => _recalcAllUsers(),
                        icon: _recalculating
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.autorenew_rounded),
                        label: const Text('Recalcular todos'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _timelineStrip(sorted),
            ...sorted.reversed.map((p) {
              final status = _statusLabel(p, sorted);
              final theme = _statusTheme(status);
              final until = p.effectiveUntil(sorted);
              return Container(
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: theme.accent.withValues(alpha: 0.35)),
                  boxShadow: [
                    BoxShadow(
                      color: theme.accent.withValues(alpha: 0.12),
                      blurRadius: 14,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 6,
                        decoration: BoxDecoration(
                          color: theme.accent,
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(18),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      p.label,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: theme.bg,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(theme.icon,
                                            size: 14, color: theme.fg),
                                        const SizedBox(width: 4),
                                        Text(
                                          status,
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w800,
                                            color: theme.fg,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _metaRow(
                                Icons.play_arrow_rounded,
                                'Início',
                                DateFormat('dd/MM/yyyy HH:mm')
                                    .format(p.effectiveFrom),
                              ),
                              _metaRow(
                                Icons.stop_rounded,
                                'Até',
                                _formatUntil(until),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Seg: diurno ${CurrencyFormats.formatBRL(p.rates.diurnoForWeekday(1))} '
                                '• noturno ${CurrencyFormats.formatBRL(p.rates.noturnoForWeekday(1))}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ),
                              if (p.notes != null && p.notes!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  p.notes!,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: theme.fg.withValues(alpha: 0.85),
                                  ),
                                ),
                              ],
                              const SizedBox(height: 10),
                              Align(
                                alignment: Alignment.centerRight,
                                child: FilledButton.tonalIcon(
                                  onPressed: () =>
                                      _openPeriodEditor(existing: p),
                                  icon: const Icon(Icons.edit_rounded, size: 18),
                                  label: const Text('Editar'),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Widget _metaRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: widget.brandTeal),
          const SizedBox(width: 6),
          Text(
            '$label: ',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
