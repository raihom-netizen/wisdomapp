import 'package:flutter/material.dart';

import '../models/scale_rates.dart';
import '../models/scale_rates_period.dart';
import '../theme/app_colors.dart';
import '../constants/currency_formats.dart';
import '../constants/date_time_formats.dart';
import 'br_datetime_input.dart';
import 'brl_amount_text_field.dart';
import 'fast_text_field.dart';

/// Editor fullscreen de período AC4 — mobile-first, tabela completa na tela.
class AdminScaleRatesPeriodEditorPage extends StatefulWidget {
  const AdminScaleRatesPeriodEditorPage({
    super.key,
    required this.brandBlue,
    required this.brandTeal,
    this.existing,
    this.isLegacySeed = false,
  });

  final Color brandBlue;
  final Color brandTeal;
  final ScaleRatesPeriod? existing;
  final bool isLegacySeed;

  @override
  State<AdminScaleRatesPeriodEditorPage> createState() =>
      _AdminScaleRatesPeriodEditorPageState();
}

class _AdminScaleRatesPeriodEditorPageState
    extends State<AdminScaleRatesPeriodEditorPage> {
  static const _weekdayLabels = [
    'Dom',
    'Seg',
    'Ter',
    'Qua',
    'Qui',
    'Sex',
    'Sáb',
  ];

  late final TextEditingController _idCtrl;
  late final TextEditingController _labelCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _nightStartCtrl;
  late final TextEditingController _nightEndCtrl;
  late final List<TextEditingController> _diurnoCtrls;
  late final List<TextEditingController> _noturnoCtrls;
  late final TextEditingController _effectiveDateCtrl;
  late final TextEditingController _effectiveTimeCtrl;
  late DateTime _effectiveDate;

  bool get _isNew => widget.existing == null;

  static String _normalizeTimeDisplay(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '00:00:00';
    final parts = t.split(':');
    if (parts.length >= 3) return t;
    if (parts.length == 2) return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}:00';
    return '00:00:00';
  }

  static String _timeForRatesField(String raw) {
    final parsed = parseBrTimeInput(raw);
    if (parsed == null) return raw.trim().isEmpty ? '22:00' : raw.trim();
    return '${parsed.hour.toString().padLeft(2, '0')}:${parsed.minute.toString().padLeft(2, '0')}';
  }

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final base = existing?.rates ?? ScaleRates.defaultRates;
    _idCtrl = TextEditingController(
      text: existing?.id ??
          (widget.isLegacySeed
              ? 'ac4_jun2024'
              : 'reajuste_${DateTime.now().millisecondsSinceEpoch}'),
    );
    _labelCtrl = TextEditingController(
      text: existing?.label ??
          (widget.isLegacySeed ? 'ANEXO I — jun/2024' : 'Novo reajuste AC4'),
    );
    _notesCtrl = TextEditingController(text: existing?.notes ?? '');
    _effectiveDate = existing?.effectiveFrom ??
        (widget.isLegacySeed
            ? DateTime(2024, 6, 1, 0, 0)
            : DateTime(2026, 7, 1, 0, 0));
    _effectiveDateCtrl = TextEditingController();
    _effectiveTimeCtrl = TextEditingController();
    syncBrDateTimeControllers(_effectiveDate, _effectiveDateCtrl, _effectiveTimeCtrl);
    _nightStartCtrl = TextEditingController(
      text: _normalizeTimeDisplay(base.nightStart),
    );
    _nightEndCtrl = TextEditingController(
      text: _normalizeTimeDisplay(base.nightEnd),
    );
    _diurnoCtrls = List.generate(
      7,
      (i) => TextEditingController(text: CurrencyFormats.formatBRLInput(base.valueDiurno[i])),
    );
    _noturnoCtrls = List.generate(
      7,
      (i) =>
          TextEditingController(text: CurrencyFormats.formatBRLInput(base.valueNoturno[i])),
    );
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    _labelCtrl.dispose();
    _notesCtrl.dispose();
    _nightStartCtrl.dispose();
    _nightEndCtrl.dispose();
    _effectiveDateCtrl.dispose();
    _effectiveTimeCtrl.dispose();
    for (final c in _diurnoCtrls) {
      c.dispose();
    }
    for (final c in _noturnoCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickEffectiveDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _effectiveDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      helpText: 'Início da vigência',
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_effectiveDate),
      helpText: 'Hora de início',
    );
    if (t == null) return;
    setState(() {
      _effectiveDate = DateTime(
        d.year,
        d.month,
        d.day,
        t.hour,
        t.minute,
        _effectiveDate.second,
      );
      syncBrDateTimeControllers(_effectiveDate, _effectiveDateCtrl, _effectiveTimeCtrl);
    });
  }

  void _applyEffectiveFromFields() {
    final combined = combineBrDateAndTime(_effectiveDateCtrl.text, _effectiveTimeCtrl.text);
    if (combined != null) {
      setState(() => _effectiveDate = combined);
    }
  }

  ScaleRatesPeriod? _buildPeriod() {
    _applyEffectiveFromFields();
    final diurno = _diurnoCtrls
        .map((c) => CurrencyFormats.parseBRLInput(c.text) ?? 0)
        .toList();
    final noturno = _noturnoCtrls
        .map((c) => CurrencyFormats.parseBRLInput(c.text) ?? 0)
        .toList();
    final id = _idCtrl.text.trim().isEmpty
        ? 'period_${_effectiveDate.millisecondsSinceEpoch}'
        : _idCtrl.text.trim();
    final label =
        _labelCtrl.text.trim().isEmpty ? 'Período AC4' : _labelCtrl.text.trim();
    final notes = _notesCtrl.text.trim();
    return ScaleRatesPeriod(
      id: id,
      label: label,
      effectiveFrom: _effectiveDate,
      rates: ScaleRates(
        nightStart: _timeForRatesField(_nightStartCtrl.text),
        nightEnd: _timeForRatesField(_nightEndCtrl.text),
        valueDiurno: diurno,
        valueNoturno: noturno,
      ),
      notes: notes.isEmpty ? null : notes,
    );
  }

  void _save() {
    final period = _buildPeriod();
    if (period == null) return;
    Navigator.pop(context, period);
  }

  @override
  Widget build(BuildContext context) {
    final title = _isNew
        ? (widget.isLegacySeed ? 'Criar período base' : 'Agendar reajuste')
        : 'Editar período';

    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FA),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 148,
            pinned: true,
            stretch: true,
            backgroundColor: widget.brandBlue,
            foregroundColor: Colors.white,
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            flexibleSpace: FlexibleSpaceBar(
              titlePadding: const EdgeInsetsDirectional.only(
                start: 56,
                bottom: 16,
                end: 16,
              ),
              title: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      widget.brandBlue,
                      widget.brandTeal,
                      AppColors.logoOrange.withValues(alpha: 0.85),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Align(
                  alignment: Alignment.bottomRight,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 20, bottom: 52),
                    child: Icon(
                      Icons.table_chart_rounded,
                      size: 56,
                      color: Colors.white.withValues(alpha: 0.22),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _infoBanner(),
                const SizedBox(height: 16),
                _sectionCard(
                  icon: Icons.label_rounded,
                  color: widget.brandBlue,
                  title: 'Identificação',
                  child: Column(
                    children: [
                      FastTextField(
                        controller: _labelCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nome (ex: ANEXO I — jul/2026)',
                          filled: true,
                        ),
                      ),
                      const SizedBox(height: 12),
                      FastTextField(
                        controller: _idCtrl,
                        enabled: _isNew,
                        decoration: const InputDecoration(
                          labelText: 'ID interno',
                          filled: true,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  icon: Icons.event_available_rounded,
                  color: AppColors.logoOrange,
                  title: 'Início da vigência',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.logoOrange.withValues(alpha: 0.15),
                              widget.brandTeal.withValues(alpha: 0.1),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.schedule_rounded, color: AppColors.logoOrange),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                DateTimeFormats.formatDateTimeSeconds(_effectiveDate),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ),
                            FilledButton.tonalIcon(
                              onPressed: _pickEffectiveDate,
                              icon: const Icon(Icons.calendar_month_rounded, size: 18),
                              label: const Text('Calendário'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: BrDateTextField(
                              controller: _effectiveDateCtrl,
                              labelText: 'Data (dd/mm/aaaa)',
                              onChanged: (_) => _applyEffectiveFromFields(),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: BrTimeTextField(
                              controller: _effectiveTimeCtrl,
                              labelText: 'Hora (hh:mm:ss)',
                              onChanged: (_) => _applyEffectiveFromFields(),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Serviços antes deste instante usam a tabela anterior. '
                        'Ex.: reajuste em 01/07/2026 00:00:00 mantém valores antigos '
                        'até 30/06/2026 23:59:59 nos cálculos retroativos.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  icon: Icons.nightlight_round,
                  color: const Color(0xFF6366F1),
                  title: 'Período noturno (24h)',
                  child: Row(
                    children: [
                      Expanded(
                        child: BrTimeTextField(
                          controller: _nightStartCtrl,
                          labelText: 'Início (hh:mm:ss)',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: BrTimeTextField(
                          controller: _nightEndCtrl,
                          labelText: 'Fim (hh:mm:ss)',
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _sectionCard(
                  icon: Icons.payments_rounded,
                  color: const Color(0xFF10B981),
                  title: 'Valores por dia (R\$/h)',
                  child: Column(
                    children: List.generate(7, (i) {
                      final isWeekend = i == 0 || i >= 5;
                      return Container(
                        margin: EdgeInsets.only(bottom: i < 6 ? 10 : 0),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isWeekend
                              ? const Color(0xFFFFF7ED)
                              : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isWeekend
                                ? AppColors.logoOrange.withValues(alpha: 0.25)
                                : Colors.grey.shade200,
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 44,
                              child: Text(
                                _weekdayLabels[i],
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: isWeekend
                                      ? AppColors.logoOrange
                                      : widget.brandBlue,
                                ),
                              ),
                            ),
                            Expanded(
                              child: BrlAmountTextField(
                                controller: _diurnoCtrls[i],
                                decoration: InputDecoration(
                                  labelText: 'Diurno',
                                  prefixText: 'R\$ ',
                                  isDense: true,
                                  filled: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: BrlAmountTextField(
                                controller: _noturnoCtrls[i],
                                decoration: InputDecoration(
                                  labelText: 'Noturno',
                                  prefixText: 'R\$ ',
                                  isDense: true,
                                  filled: true,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
                const SizedBox(height: 14),
                FastTextField(
                  controller: _notesCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Observações (opcional)',
                    filled: true,
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: widget.brandBlue,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Salvar período',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFDCFCE7),
            widget.brandTeal.withValues(alpha: 0.15),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF86EFAC)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_rounded, color: Color(0xFF15803D)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Segurança nas escalas: plantões até 30/06/2026 23:59 usam a tabela '
              'anterior; a partir de 01/07/2026 00:00 entram os novos valores. '
              'Plantões noturnos que cruzam a meia-noite são calculados minuto a minuto.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: Colors.green.shade900,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required IconData icon,
    required Color color,
    required String title,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}
