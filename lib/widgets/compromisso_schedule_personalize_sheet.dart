import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';
import '../utils/compromisso_schedule_dates.dart';
import 'multi_date_month_picker_dialog.dart';

enum _ScheduleScope { thisMonth, restOfYear, fullYear, customPeriod }

/// Personalizar datas: dia da semana, mês, ano ou período (férias).
Future<List<DateTime>?> showCompromissoSchedulePersonalizeSheet({
  required BuildContext context,
  required DateTime referenceMonth,
  List<DateTime>? initialSelected,
}) {
  return showModalBottomSheet<List<DateTime>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _CompromissoSchedulePersonalizeBody(
      referenceMonth: referenceMonth,
      initialSelected: initialSelected ?? const [],
    ),
  );
}

class _CompromissoSchedulePersonalizeBody extends StatefulWidget {
  const _CompromissoSchedulePersonalizeBody({
    required this.referenceMonth,
    required this.initialSelected,
  });

  final DateTime referenceMonth;
  final List<DateTime> initialSelected;

  @override
  State<_CompromissoSchedulePersonalizeBody> createState() =>
      _CompromissoSchedulePersonalizeBodyState();
}

class _CompromissoSchedulePersonalizeBodyState
    extends State<_CompromissoSchedulePersonalizeBody> {
  static const _weekdayLabels = {
    DateTime.monday: 'Seg',
    DateTime.tuesday: 'Ter',
    DateTime.wednesday: 'Qua',
    DateTime.thursday: 'Qui',
    DateTime.friday: 'Sex',
    DateTime.saturday: 'Sáb',
    DateTime.sunday: 'Dom',
  };

  final Set<int> _weekdays = {};
  _ScheduleScope _scope = _ScheduleScope.thisMonth;
  late DateTime _periodStart;
  late DateTime _periodEnd;

  @override
  void initState() {
    super.initState();
    final ref = CompromissoScheduleDates.norm(widget.referenceMonth);
    _periodStart = ref;
    _periodEnd = ref.add(const Duration(days: 6));
  }

  List<DateTime> get _preview {
    if (_weekdays.isEmpty) return const [];
    final ref = CompromissoScheduleDates.norm(widget.referenceMonth);
    late DateTime start;
    late DateTime end;
    switch (_scope) {
      case _ScheduleScope.thisMonth:
        start = CompromissoScheduleDates.monthStart(ref);
        end = CompromissoScheduleDates.monthEnd(ref);
      case _ScheduleScope.restOfYear:
        start = CompromissoScheduleDates.restOfYearStart(DateTime.now());
        end = CompromissoScheduleDates.yearEnd(ref);
      case _ScheduleScope.fullYear:
        start = CompromissoScheduleDates.yearStart(ref);
        end = CompromissoScheduleDates.yearEnd(ref);
      case _ScheduleScope.customPeriod:
        start = CompromissoScheduleDates.norm(_periodStart);
        end = CompromissoScheduleDates.norm(_periodEnd);
    }
    return CompromissoScheduleDates.weekdaysInRange(
      weekdays: _weekdays,
      rangeStart: start,
      rangeEnd: end,
    );
  }

  Future<void> _pickPeriodDay({required bool start}) async {
    final initial = start ? _periodStart : _periodEnd;
    final picked = await pickSingleDateWithHolidayCalendar(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _periodStart = picked;
        if (_periodEnd.isBefore(_periodStart)) _periodEnd = _periodStart;
      } else {
        _periodEnd = picked;
        if (_periodEnd.isBefore(_periodStart)) _periodStart = _periodEnd;
      }
    });
  }

  Future<void> _pickPeriodRangeAllDays() async {
    final start = await pickSingleDateWithHolidayCalendar(
      context: context,
      initialDate: _periodStart,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (start == null || !mounted) return;
    final end = await pickSingleDateWithHolidayCalendar(
      context: context,
      initialDate: _periodEnd.isBefore(start) ? start : _periodEnd,
      firstDate: start,
      lastDate: DateTime(2100),
    );
    if (end == null || !mounted) return;
    final days = CompromissoScheduleDates.daysInPeriod(start, end);
    if (days.isEmpty) return;
    Navigator.pop(context, CompromissoScheduleDates.uniqueSorted([
      ...widget.initialSelected,
      ...days,
    ]));
  }

  void _confirmWeekdays() {
    final generated = _preview;
    if (generated.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marque ao menos um dia da semana.')),
      );
      return;
    }
    Navigator.pop(
      context,
      CompromissoScheduleDates.uniqueSorted([
        ...widget.initialSelected,
        ...generated,
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final refLabel =
        DateFormat('MMMM yyyy', 'pt_BR').format(widget.referenceMonth);
    final previewCount = _preview.length;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.45,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFFF1F5F9),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Personalizar datas',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: AppColors.deepBlue,
                            ),
                          ),
                          Text(
                            'Referência: $refLabel',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  children: [
                    _sectionCard(
                      title: 'Período contínuo (férias, viagem…)',
                      subtitle:
                          'Marca todos os dias entre duas datas — ideal para férias.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pickPeriodRangeAllDays,
                            icon: const Icon(Icons.date_range_rounded),
                            label: const Text(
                              'Escolher início e fim do período',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    _sectionCard(
                      title: 'Dia da semana',
                      subtitle:
                          'Ex.: toda terça deste mês, ou todas as segundas do ano.',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: _weekdayLabels.entries.map((e) {
                              final sel = _weekdays.contains(e.key);
                              return FilterChip(
                                label: Text(e.value),
                                selected: sel,
                                onSelected: (v) {
                                  setState(() {
                                    if (v) {
                                      _weekdays.add(e.key);
                                    } else {
                                      _weekdays.remove(e.key);
                                    }
                                  });
                                },
                                selectedColor:
                                    AppColors.primary.withValues(alpha: 0.18),
                                checkmarkColor: AppColors.primary,
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 12),
                          ..._scopeTile(
                            _ScheduleScope.thisMonth,
                            'Somente este mês',
                            Icons.calendar_view_month_rounded,
                          ),
                          ..._scopeTile(
                            _ScheduleScope.restOfYear,
                            'Restante deste ano',
                            Icons.calendar_today_rounded,
                          ),
                          ..._scopeTile(
                            _ScheduleScope.fullYear,
                            'Ano inteiro',
                            Icons.event_repeat_rounded,
                          ),
                          ..._scopeTile(
                            _ScheduleScope.customPeriod,
                            'Período personalizado',
                            Icons.edit_calendar_rounded,
                          ),
                          if (_scope == _ScheduleScope.customPeriod) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _pickPeriodDay(start: true),
                                    child: Text(
                                      'De ${DateFormat('dd/MM/yy').format(_periodStart)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _pickPeriodDay(start: false),
                                    child: Text(
                                      'Até ${DateFormat('dd/MM/yy').format(_periodEnd)}',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (_weekdays.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                previewCount == 0
                                    ? 'Nenhum dia neste intervalo.'
                                    : '$previewCount dia(s) serão adicionados à seleção.',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                  color: AppColors.deepBlue,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            FilledButton.icon(
                              onPressed: _confirmWeekdays,
                              icon: const Icon(Icons.check_rounded),
                              label: const Text(
                                'Adicionar dias da semana',
                                style: TextStyle(fontWeight: FontWeight.w900),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                minimumSize: const Size(double.infinity, 46),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.initialSelected.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Já selecionados: ${widget.initialSelected.length} dia(s)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _scopeTile(
    _ScheduleScope scope,
    String label,
    IconData icon,
  ) {
    return [
      RadioListTile<_ScheduleScope>(
        value: scope,
        groupValue: _scope,
        onChanged: (v) => setState(() => _scope = v ?? scope),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        secondary: Icon(icon, color: AppColors.primary, size: 22),
        dense: true,
        contentPadding: EdgeInsets.zero,
      ),
    ];
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 15,
                color: AppColors.deepBlue,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                height: 1.3,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
