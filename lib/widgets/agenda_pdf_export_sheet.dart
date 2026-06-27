import 'package:flutter/material.dart';

import '../services/relatorio_service.dart';
import '../theme/app_colors.dart';

/// Opções escolhidas no sheet de exportação PDF da Agenda.
class AgendaPdfExportOptions {
  const AgendaPdfExportOptions({
    required this.contentFilter,
    required this.rangeStart,
    required this.rangeEnd,
    required this.useFocusedMonth,
  });

  final AgendaPdfContentFilter contentFilter;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final bool useFocusedMonth;
}

/// Sheet: PDF financeiro, particular ou completo — mês visível ou período.
class AgendaPdfExportSheet extends StatefulWidget {
  const AgendaPdfExportSheet({
    super.key,
    required this.focusedDay,
    this.initialFilter = AgendaPdfContentFilter.todos,
  });

  final DateTime focusedDay;
  final AgendaPdfContentFilter initialFilter;

  static Future<AgendaPdfExportOptions?> show(
    BuildContext context, {
    required DateTime focusedDay,
    AgendaPdfContentFilter initialFilter = AgendaPdfContentFilter.todos,
  }) {
    return showModalBottomSheet<AgendaPdfExportOptions>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AgendaPdfExportSheet(
        focusedDay: focusedDay,
        initialFilter: initialFilter,
      ),
    );
  }

  @override
  State<AgendaPdfExportSheet> createState() => _AgendaPdfExportSheetState();
}

class _AgendaPdfExportSheetState extends State<AgendaPdfExportSheet> {
  late AgendaPdfContentFilter _filter = widget.initialFilter;
  bool _useMonth = true;
  DateTime? _customStart;
  DateTime? _customEnd;

  DateTime get _monthStart =>
      DateTime(widget.focusedDay.year, widget.focusedDay.month, 1);
  DateTime get _monthEnd =>
      DateTime(widget.focusedDay.year, widget.focusedDay.month + 1, 0);

  Future<void> _pickRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035, 12, 31),
      initialDateRange: DateTimeRange(
        start: _customStart ?? _monthStart,
        end: _customEnd ?? _monthEnd,
      ),
      helpText: 'Período do PDF',
      saveText: 'Confirmar',
      locale: const Locale('pt', 'BR'),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _useMonth = false;
      _customStart = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _customEnd = DateTime(
        picked.end.year,
        picked.end.month,
        picked.end.day,
      );
    });
  }

  void _confirm() {
    final start = _useMonth
        ? _monthStart
        : (_customStart ?? _monthStart);
    final end = _useMonth
        ? _monthEnd
        : (_customEnd ?? _monthEnd);
    Navigator.of(context).pop(
      AgendaPdfExportOptions(
        contentFilter: _filter,
        rangeStart: start,
        rangeEnd: end,
        useFocusedMonth: _useMonth,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(22),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              const Row(
                children: [
                  Icon(Icons.picture_as_pdf_rounded, color: Color(0xFFE65100)),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Exportar PDF da Agenda',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Conteúdo',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<AgendaPdfContentFilter>(
                segments: const [
                  ButtonSegment(
                    value: AgendaPdfContentFilter.financeiro,
                    label: Text('Financeiro', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.payments_outlined, size: 16),
                  ),
                  ButtonSegment(
                    value: AgendaPdfContentFilter.particular,
                    label: Text('Particular', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.event_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: AgendaPdfContentFilter.todos,
                    label: Text('Todos', style: TextStyle(fontSize: 11)),
                    icon: Icon(Icons.all_inclusive_rounded, size: 16),
                  ),
                ],
                selected: {_filter},
                onSelectionChanged: (s) => setState(() => _filter = s.first),
              ),
              const SizedBox(height: 16),
              Text(
                'Período',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'Mês visível no calendário',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                subtitle: Text(
                  '${_monthStart.day.toString().padLeft(2, '0')}/${_monthStart.month.toString().padLeft(2, '0')}/${_monthStart.year}'
                  ' — '
                  '${_monthEnd.day.toString().padLeft(2, '0')}/${_monthEnd.month.toString().padLeft(2, '0')}/${_monthEnd.year}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                value: _useMonth,
                activeTrackColor: AppColors.primary.withValues(alpha: 0.45),
                onChanged: (v) => setState(() => _useMonth = v),
              ),
              if (!_useMonth)
                OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text(
                    _customStart != null && _customEnd != null
                        ? '${_customStart!.day.toString().padLeft(2, '0')}/${_customStart!.month.toString().padLeft(2, '0')}/${_customStart!.year}'
                          ' — '
                          '${_customEnd!.day.toString().padLeft(2, '0')}/${_customEnd!.month.toString().padLeft(2, '0')}/${_customEnd!.year}'
                        : 'Escolher intervalo de datas',
                  ),
                ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _confirm,
                icon: const Icon(Icons.picture_as_pdf_rounded),
                label: const Text('Gerar PDF'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
