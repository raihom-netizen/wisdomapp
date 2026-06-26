import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart' hide showDatePicker;
import 'fast_text_field.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../utils/date_picker_a11y.dart';

/// Períodos do painel / módulo Audiências e Compromissos.
class AgendaPeriodKeys {
  AgendaPeriodKeys._();
  static const mesAtual = 'Mês atual';
  static const anual = 'Anual';
  static const porPeriodo = 'Por período';
  static const all = [mesAtual, anual, porPeriodo];
}

/// Valor atual do filtro de período (intervalo + rótulo).
class AgendaPeriodFilterValue {
  final String period;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final String label;

  const AgendaPeriodFilterValue({
    required this.period,
    required this.rangeStart,
    required this.rangeEnd,
    required this.label,
  });
}

DateTime? agendaParseBrDateInput(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  for (final pattern in ['dd/MM/yyyy', 'dd/MM/yy', 'd/M/yyyy', 'd/M/yy']) {
    try {
      return DateFormat(pattern, 'pt_BR').parseStrict(t);
    } catch (_) {}
  }
  return null;
}

(DateTime, DateTime) agendaPeriodRangeFor({
  required String period,
  DateTime? customStart,
  DateTime? customEnd,
}) {
  final now = DateTime.now();
  switch (period) {
    case AgendaPeriodKeys.anual:
      return (
        DateTime(now.year, 1, 1),
        DateTime(now.year, 12, 31, 23, 59, 59),
      );
    case AgendaPeriodKeys.porPeriodo:
      final start = customStart ?? DateTime(now.year, now.month, 1);
      final end = customEnd ?? now;
      final endNorm = end.isBefore(start) ? start : end;
      return (
        DateTime(start.year, start.month, start.day),
        DateTime(endNorm.year, endNorm.month, endNorm.day, 23, 59, 59),
      );
    case AgendaPeriodKeys.mesAtual:
    default:
      return (
        DateTime(now.year, now.month, 1),
        DateTime(now.year, now.month + 1, 0, 23, 59, 59),
      );
  }
}

String agendaPeriodLabelFor({
  required String period,
  required DateTime rangeStart,
  required DateTime rangeEnd,
}) {
  switch (period) {
    case AgendaPeriodKeys.mesAtual:
      return DateFormat('MMMM/yyyy', 'pt_BR').format(rangeStart);
    case AgendaPeriodKeys.anual:
      return 'Ano ${rangeStart.year}';
    case AgendaPeriodKeys.porPeriodo:
      return '${DateFormat('dd/MM/yyyy', 'pt_BR').format(rangeStart)} – '
          '${DateFormat('dd/MM/yyyy', 'pt_BR').format(rangeEnd)}';
    default:
      return DateFormat('dd/MM/yyyy', 'pt_BR').format(rangeStart);
  }
}

AgendaPeriodFilterValue agendaPeriodFilterValue({
  required String period,
  DateTime? customStart,
  DateTime? customEnd,
}) {
  final (a, b) = agendaPeriodRangeFor(
    period: period,
    customStart: customStart,
    customEnd: customEnd,
  );
  return AgendaPeriodFilterValue(
    period: period,
    rangeStart: a,
    rangeEnd: b,
    label: agendaPeriodLabelFor(period: period, rangeStart: a, rangeEnd: b),
  );
}

/// Data do lembrete (campo `date` + opcional `time`) para filtro de período.
DateTime? agendaReminderDateTime(Map<String, dynamic> data) {
  final date = (data['date'] as Timestamp?)?.toDate();
  if (date == null) return null;
  final timeStr = (data['time'] ?? '').toString().trim();
  if (timeStr.isEmpty) return DateTime(date.year, date.month, date.day);
  final parts = timeStr.split(':');
  if (parts.length < 2) return DateTime(date.year, date.month, date.day);
  final h = int.tryParse(parts[0]) ?? 0;
  final m = int.tryParse(parts[1]) ?? 0;
  return DateTime(date.year, date.month, date.day, h, m);
}

bool agendaReminderDayInRange(
  Map<String, dynamic> data,
  DateTime rangeStart,
  DateTime rangeEnd,
) {
  final dt = agendaReminderDateTime(data);
  if (dt == null) return false;
  final day = DateTime(dt.year, dt.month, dt.day);
  final s = DateTime(rangeStart.year, rangeStart.month, rangeStart.day);
  final e = DateTime(rangeEnd.year, rangeEnd.month, rangeEnd.day);
  return !day.isBefore(s) && !day.isAfter(e);
}

/// Visual da barra: fundo claro (módulo Agenda) ou sobre gradiente (legado).
enum AgendaPeriodFilterBarStyle {
  standard,
  onGradient,
}

/// [segmented] = três botões estreitos na mesma linha (painel Início).
enum AgendaPeriodFilterBarLayout {
  wrap,
  segmented,
}

/// Barra premium: Mês atual (padrão), Anual, Por período + calendário e digitação.
class AgendaPeriodFilterBar extends StatefulWidget {
  final String initialPeriod;
  final DateTime? initialCustomStart;
  final DateTime? initialCustomEnd;
  final ValueChanged<AgendaPeriodFilterValue> onChanged;
  final bool dense;
  final AgendaPeriodFilterBarStyle style;
  final AgendaPeriodFilterBarLayout layout;

  const AgendaPeriodFilterBar({
    super.key,
    this.initialPeriod = AgendaPeriodKeys.anual,
    this.initialCustomStart,
    this.initialCustomEnd,
    required this.onChanged,
    this.dense = false,
    this.style = AgendaPeriodFilterBarStyle.standard,
    this.layout = AgendaPeriodFilterBarLayout.wrap,
  });

  @override
  State<AgendaPeriodFilterBar> createState() => _AgendaPeriodFilterBarState();
}

class _AgendaPeriodFilterBarState extends State<AgendaPeriodFilterBar> {
  late String _period;
  DateTime? _customStart;
  DateTime? _customEnd;
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;

  @override
  void initState() {
    super.initState();
    _period = widget.initialPeriod;
    final now = DateTime.now();
    _customStart = widget.initialCustomStart ?? DateTime(now.year, now.month, 1);
    _customEnd = widget.initialCustomEnd ?? now;
    _startCtrl = TextEditingController(
      text: DateFormat('dd/MM/yyyy', 'pt_BR').format(_customStart!),
    );
    _endCtrl = TextEditingController(
      text: DateFormat('dd/MM/yyyy', 'pt_BR').format(_customEnd!),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _emit());
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    widget.onChanged(
      agendaPeriodFilterValue(
        period: _period,
        customStart: _customStart,
        customEnd: _customEnd,
      ),
    );
  }

  void _setPeriod(String p) {
    setState(() {
      _period = p;
      if (p == AgendaPeriodKeys.porPeriodo) {
        final now = DateTime.now();
        _customStart ??= DateTime(now.year, now.month, 1);
        _customEnd ??= now;
        _startCtrl.text = DateFormat('dd/MM/yyyy', 'pt_BR').format(_customStart!);
        _endCtrl.text = DateFormat('dd/MM/yyyy', 'pt_BR').format(_customEnd!);
      }
    });
    _emit();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart
        ? (_customStart ?? DateTime.now())
        : (_customEnd ?? _customStart ?? DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
      helpText: isStart ? 'Data inicial' : 'Data final',
      fieldHintText: 'dd/mm/aaaa',
      fieldLabelText: isStart ? 'Início' : 'Fim',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isStart) {
        _customStart = picked;
        _startCtrl.text = DateFormat('dd/MM/yyyy', 'pt_BR').format(picked);
        if (_customEnd != null && _customEnd!.isBefore(picked)) {
          _customEnd = picked;
          _endCtrl.text = _startCtrl.text;
        }
      } else {
        _customEnd = picked;
        _endCtrl.text = DateFormat('dd/MM/yyyy', 'pt_BR').format(picked);
      }
    });
    _emit();
  }

  void _applyTypedDate({required bool isStart}) {
    final parsed = agendaParseBrDateInput(isStart ? _startCtrl.text : _endCtrl.text);
    if (parsed == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text('Data inválida. Use dd/mm/aaaa (ex.: 15/05/2026).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    setState(() {
      if (isStart) {
        _customStart = parsed;
        if (_customEnd != null && _customEnd!.isBefore(parsed)) {
          _customEnd = parsed;
          _endCtrl.text = _startCtrl.text;
        }
      } else {
        _customEnd = parsed;
      }
    });
    _emit();
  }

  bool get _onGradient => widget.style == AgendaPeriodFilterBarStyle.onGradient;

  Widget _periodChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    bool expanded = false,
  }) {
    final chipRadius = widget.layout == AgendaPeriodFilterBarLayout.segmented
        ? 14.0
        : 16.0;
    final minH = widget.layout == AgendaPeriodFilterBarLayout.segmented
        ? (widget.dense ? 36.0 : 40.0)
        : 48.0;
    final Color iconColor;
    final Color textColor;
    final BoxDecoration decoration;
    if (_onGradient) {
      iconColor = selected ? AppColors.deepBlueDark : Colors.white;
      textColor = selected ? AppColors.deepBlueDark : Colors.white;
      decoration = BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: selected ? Colors.white : Colors.white.withValues(alpha: 0.14),
        border: Border.all(
          color: selected
              ? Colors.white
              : Colors.white.withValues(alpha: 0.45),
        ),
        boxShadow: selected
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      );
    } else {
      final segmented =
          widget.layout == AgendaPeriodFilterBarLayout.segmented;
      final accent = AppColors.primary;
      if (segmented) {
        iconColor = selected ? accent : AppColors.textMuted;
        textColor = selected ? accent : AppColors.textSecondary;
        decoration = BoxDecoration(
          borderRadius: BorderRadius.circular(chipRadius),
          color: selected
              ? accent.withValues(alpha: 0.12)
              : const Color(0xFFF8FAFC),
          border: Border.all(
            color: selected ? accent : const Color(0xFFE2E8F0),
            width: selected ? 2 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: accent.withValues(alpha: 0.16),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        );
      } else {
        iconColor = selected ? Colors.white : AppColors.primary;
        textColor = selected ? Colors.white : AppColors.primary;
        decoration = BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: selected
              ? const LinearGradient(
                  colors: [
                    AppColors.deepBlueDark,
                    AppColors.primary,
                    AppColors.accent,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: selected ? null : const Color(0xFFF8FAFC),
          border: Border.all(
            color: selected ? Colors.transparent : const Color(0xFFE2E8F0),
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: AppColors.deepBlueDark.withValues(alpha: 0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        );
      }
    }
    final chip = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(chipRadius),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          constraints: BoxConstraints(minHeight: minH),
          padding: EdgeInsets.symmetric(
            horizontal: expanded ? 6 : (widget.dense ? 10 : 12),
            vertical: expanded ? 6 : (widget.dense ? 8 : 10),
          ),
          decoration: decoration,
          child: Row(
            mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment:
                expanded ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              Icon(icon, size: expanded ? 15 : 17, color: iconColor),
              SizedBox(width: expanded ? 4 : 6),
              Flexible(
                fit: expanded ? FlexFit.loose : FlexFit.loose,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: expanded
                        ? 11
                        : (widget.dense ? 12 : 13),
                    fontWeight: FontWeight.w800,
                    color: textColor,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign:
                      expanded ? TextAlign.center : TextAlign.start,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (!expanded) return chip;
    return Expanded(child: chip);
  }

  @override
  Widget build(BuildContext context) {
    final value = agendaPeriodFilterValue(
      period: _period,
      customStart: _customStart,
      customEnd: _customEnd,
    );

    final showPorPeriodo = _period == AgendaPeriodKeys.porPeriodo;

    Widget periodChipsRow() {
      if (widget.layout == AgendaPeriodFilterBarLayout.segmented) {
        return Row(
          children: [
            _periodChip(
              label: 'Mês',
              icon: Icons.calendar_month_rounded,
              selected: _period == AgendaPeriodKeys.mesAtual,
              onTap: () => _setPeriod(AgendaPeriodKeys.mesAtual),
              expanded: true,
            ),
            const SizedBox(width: 6),
            _periodChip(
              label: 'Anual',
              icon: Icons.calendar_view_month_rounded,
              selected: _period == AgendaPeriodKeys.anual,
              onTap: () => _setPeriod(AgendaPeriodKeys.anual),
              expanded: true,
            ),
            const SizedBox(width: 6),
            _periodChip(
              label: 'Período',
              icon: Icons.date_range_rounded,
              selected: showPorPeriodo,
              onTap: () => _setPeriod(AgendaPeriodKeys.porPeriodo),
              expanded: true,
            ),
          ],
        );
      }
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.start,
        children: [
          _periodChip(
            label: AgendaPeriodKeys.mesAtual,
            icon: Icons.calendar_month_rounded,
            selected: _period == AgendaPeriodKeys.mesAtual,
            onTap: () => _setPeriod(AgendaPeriodKeys.mesAtual),
          ),
          _periodChip(
            label: AgendaPeriodKeys.anual,
            icon: Icons.calendar_view_month_rounded,
            selected: _period == AgendaPeriodKeys.anual,
            onTap: () => _setPeriod(AgendaPeriodKeys.anual),
          ),
          _periodChip(
            label: AgendaPeriodKeys.porPeriodo,
            icon: Icons.date_range_rounded,
            selected: showPorPeriodo,
            onTap: () => _setPeriod(AgendaPeriodKeys.porPeriodo),
          ),
        ],
      );
    }

    Widget dateRangeBlock(bool narrow) {
      if (narrow) {
        return Column(
          children: [
            _customDateField(
              label: 'Início',
              controller: _startCtrl,
              onCalendar: () => _pickDate(isStart: true),
              onSubmitted: () => _applyTypedDate(isStart: true),
            ),
            const SizedBox(height: 8),
            _customDateField(
              label: 'Fim',
              controller: _endCtrl,
              onCalendar: () => _pickDate(isStart: false),
              onSubmitted: () => _applyTypedDate(isStart: false),
            ),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _customDateField(
              label: 'Início',
              controller: _startCtrl,
              onCalendar: () => _pickDate(isStart: true),
              onSubmitted: () => _applyTypedDate(isStart: true),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _customDateField(
              label: 'Fim',
              controller: _endCtrl,
              onCalendar: () => _pickDate(isStart: false),
              onSubmitted: () => _applyTypedDate(isStart: false),
            ),
          ),
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            periodChipsRow(),
            if (!showPorPeriodo) ...[
              const SizedBox(height: 6),
              Text(
                value.label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _onGradient
                      ? Colors.white.withValues(alpha: 0.92)
                      : AppColors.textMuted,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: showPorPeriodo
                  ? Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: dateRangeBlock(narrow),
                    )
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }

  Widget _customDateField({
    required String label,
    required TextEditingController controller,
    required VoidCallback onCalendar,
    required VoidCallback onSubmitted,
  }) {
    final onGrad = _onGradient;
    return FastTextField(
      controller: controller,
      keyboardType: TextInputType.datetime,
      textInputAction: TextInputAction.done,
      style: onGrad
          ? const TextStyle(
              color: AppColors.deepBlueDark,
              fontWeight: FontWeight.w700,
            )
          : null,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[\d/]')),
        LengthLimitingTextInputFormatter(10),
      ],
      decoration: InputDecoration(
        isDense: true,
        labelText: label,
        labelStyle: onGrad
            ? TextStyle(color: Colors.white.withValues(alpha: 0.85))
            : null,
        hintText: 'dd/mm/aaaa',
        hintStyle: onGrad
            ? TextStyle(color: AppColors.deepBlueDark.withValues(alpha: 0.45))
            : null,
        filled: true,
        fillColor: onGrad ? Colors.white : AppColors.primary.withValues(alpha: 0.06),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: onGrad
              ? BorderSide(color: Colors.white.withValues(alpha: 0.5))
              : BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: onGrad
              ? BorderSide(color: Colors.white.withValues(alpha: 0.5))
              : BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(
            color: onGrad ? Colors.white : AppColors.primary,
            width: 2,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        suffixIcon: IconButton(
          tooltip: 'Escolher no calendário',
          onPressed: onCalendar,
          icon: Icon(
            Icons.calendar_month_rounded,
            size: 20,
            color: onGrad ? AppColors.deepBlueDark : AppColors.primary,
          ),
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
        ),
      ),
      onSubmitted: (_) => onSubmitted(),
      onEditingComplete: onSubmitted,
    );
  }
}
