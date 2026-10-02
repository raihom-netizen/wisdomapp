import 'package:flutter/material.dart';

import '../services/relatorio_service.dart';
import '../theme/app_colors.dart';
import '../theme/theme_context.dart';
import 'modern_pdf_export_button.dart';

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
    final start = _useMonth ? _monthStart : (_customStart ?? _monthStart);
    final end = _useMonth ? _monthEnd : (_customEnd ?? _monthEnd);
    Navigator.of(context).pop(
      AgendaPdfExportOptions(
        contentFilter: _filter,
        rangeStart: start,
        rangeEnd: end,
        useFocusedMonth: _useMonth,
      ),
    );
  }

  Widget _filterChip({
    required AgendaPdfContentFilter value,
    required String label,
    required IconData icon,
    required Color accent,
  }) {
    final selected = _filter == value;
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => setState(() => _filter = value),
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            decoration: BoxDecoration(
              color: selected
                  ? accent.withValues(alpha: 0.14)
                  : (context.isDarkMode ? context.appChipIdleBg : Colors.white),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: selected
                    ? accent.withValues(alpha: 0.55)
                    : (context.isDarkMode
                        ? context.appChipIdleBorder
                        : Colors.black.withValues(alpha: 0.12)),
                width: selected ? 1.6 : 1,
              ),
              boxShadow: selected
                  ? [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.18),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: accent),
                const SizedBox(height: 6),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w900,
                    color: selected ? accent : context.appTextPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
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
              Row(
                children: [
                  ModernPdfUi.iconBadge(size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Exportar PDF da Agenda',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: context.appTextPrimary,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Conteúdo',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: context.isDarkMode
                      ? context.appTextSecondary
                      : Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _filterChip(
                    value: AgendaPdfContentFilter.financeiro,
                    label: 'Financeiro',
                    icon: Icons.payments_outlined,
                    accent: AppColors.logoOrange,
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    value: AgendaPdfContentFilter.particular,
                    label: 'Particular',
                    icon: Icons.event_rounded,
                    accent: AppColors.accent,
                  ),
                  const SizedBox(width: 8),
                  _filterChip(
                    value: AgendaPdfContentFilter.todos,
                    label: 'Todos',
                    icon: Icons.grid_view_rounded,
                    accent: AppColors.primary,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Período',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: context.isDarkMode
                      ? context.appTextSecondary
                      : Colors.grey.shade700,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.deepBlue.withValues(alpha: 0.12),
                  ),
                ),
                child: SwitchListTile.adaptive(
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                  title: const Text(
                    'Mês visível no calendário',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                  ),
                  subtitle: Text(
                    '${_monthStart.day.toString().padLeft(2, '0')}/${_monthStart.month.toString().padLeft(2, '0')}/${_monthStart.year}'
                    ' — '
                    '${_monthEnd.day.toString().padLeft(2, '0')}/${_monthEnd.month.toString().padLeft(2, '0')}/${_monthEnd.year}',
                    style: TextStyle(
                      fontSize: 12,
                      color: context.isDarkMode
                          ? context.appTextMuted
                          : Colors.grey.shade600,
                    ),
                  ),
                  value: _useMonth,
                  activeTrackColor: AppColors.primary.withValues(alpha: 0.45),
                  onChanged: (v) => setState(() => _useMonth = v),
                ),
              ),
              if (!_useMonth) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _pickRange,
                  icon: const Icon(Icons.date_range_rounded),
                  label: Text(
                    _customStart != null && _customEnd != null
                        ? '${_customStart!.day.toString().padLeft(2, '0')}/${_customStart!.month.toString().padLeft(2, '0')}/${_customStart!.year}'
                          ' — '
                          '${_customEnd!.day.toString().padLeft(2, '0')}/${_customEnd!.month.toString().padLeft(2, '0')}/${_customEnd!.year}'
                        : 'Escolher intervalo de datas',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 46),
                    foregroundColor: context.isDarkMode
                        ? context.appDeepTitle
                        : AppColors.deepBlue,
                    side: BorderSide(
                      color: context.isDarkMode
                          ? context.appChipIdleBorder
                          : AppColors.deepBlue.withValues(alpha: 0.28),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              ModernPdfExportButton(
                onPressed: _confirm,
                label: 'Gerar PDF',
                subtitle: RelatorioService.agendaPdfFilterLabel(_filter),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
