import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../shared/utils/holiday_helper.dart';
import '../theme/app_colors.dart';

DateTime _normD(DateTime d) => DateTime(d.year, d.month, d.day);

String _keyD(DateTime d) => '${d.year}-${d.month}-${d.day}';

int _monthIndex(int y, int m) => y * 12 + m;

/// Diálogo para marcar **uma ou várias datas** (navegação entre meses com setas).
Future<List<DateTime>?> showMultiDateMonthPickerDialog({
  required BuildContext context,
  required DateTime month,
  List<DateTime>? initialSelected,
  /// Quando `1`, só um dia pode ficar marcado (fluxo "trocar plantão").
  int? maxSelection,
  /// Primeiro mês permitido (inclusive). `null` → jan/2020.
  DateTime? firstMonthAllowed,
  /// Último mês permitido (inclusive). `null` → dez/2100.
  DateTime? lastMonthAllowed,
  /// Limite inferior do **dia civil** clicável (inclusive). `null` → sem limite.
  DateTime? selectableMinDay,
  /// Limite superior do **dia civil** clicável (inclusive). `null` → sem limite.
  DateTime? selectableMaxDay,
}) {
  final y = month.year;
  final m = month.month;
  final initialKeys = <String>{
    for (final d in (initialSelected ?? []))
      if (d.year == y && d.month == m) _keyD(_normD(d)),
  };

  final firstM = firstMonthAllowed != null
      ? DateTime(firstMonthAllowed.year, firstMonthAllowed.month, 1)
      : DateTime(2020, 1, 1);
  final lastM = lastMonthAllowed != null
      ? DateTime(lastMonthAllowed.year, lastMonthAllowed.month, 1)
      : DateTime(2100, 12, 1);

  DateTime? minD;
  DateTime? maxD;
  if (selectableMinDay != null) {
    minD = _normD(selectableMinDay);
  }
  if (selectableMaxDay != null) {
    maxD = _normD(selectableMaxDay);
  }

  // Tela fullscreen (Scaffold) para o usuário NÃO precisar rolar para ver o
  // calendário em iPhone/Android estreitos ou web instalável. Mantém a mesma
  // API pública (Future<List<DateTime>?>), só troca o transporte.
  return Navigator.of(context, rootNavigator: true).push<List<DateTime>>(
    MaterialPageRoute<List<DateTime>>(
      fullscreenDialog: true,
      builder: (ctx) => _MultiDateMonthBody(
        year: y,
        month: m,
        initialKeys: initialKeys,
        maxSelection: maxSelection,
        firstMonthIndex: _monthIndex(firstM.year, firstM.month),
        lastMonthIndex: _monthIndex(lastM.year, lastM.month),
        selectableMinDay: minD,
        selectableMaxDay: maxD,
      ),
    ),
  );
}

/// Um único dia — mesmo calendário (fins de semana e feriados em vermelho negrito + rodapé com feriados do mês).
Future<DateTime?> pickSingleDateWithHolidayCalendar({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) async {
  final minD = _normD(firstDate);
  final maxD = _normD(lastDate);
  var init = _normD(initialDate);
  if (init.isBefore(minD)) init = minD;
  if (init.isAfter(maxD)) init = maxD;

  final list = await showMultiDateMonthPickerDialog(
    context: context,
    month: init,
    initialSelected: [init],
    maxSelection: 1,
    firstMonthAllowed: DateTime(firstDate.year, firstDate.month, 1),
    lastMonthAllowed: DateTime(lastDate.year, lastDate.month, 1),
    selectableMinDay: minD,
    selectableMaxDay: maxD,
  );
  if (list == null || list.isEmpty) return null;
  return _normD(list.first);
}

class _MultiDateMonthBody extends StatefulWidget {
  final int year;
  final int month;
  final Set<String> initialKeys;
  final int? maxSelection;
  final int firstMonthIndex;
  final int lastMonthIndex;
  final DateTime? selectableMinDay;
  final DateTime? selectableMaxDay;

  const _MultiDateMonthBody({
    required this.year,
    required this.month,
    required this.initialKeys,
    this.maxSelection,
    required this.firstMonthIndex,
    required this.lastMonthIndex,
    this.selectableMinDay,
    this.selectableMaxDay,
  });

  @override
  State<_MultiDateMonthBody> createState() => _MultiDateMonthBodyState();
}

class _MultiDateMonthBodyState extends State<_MultiDateMonthBody> {
  late int _viewYear;
  late int _viewMonth;
  late Set<String> _selected;
  late Set<String> _holidayKeys;

  /// Vermelho **negrito** para sáb/dom e feriados (contraste sobre fundo claro).
  static const Color _weekendHolidayRed = Color(0xFFC62828);

  /// Botões ◀ ▶ — gradiente logo (super premium), ícone branco e sombra suave.
  Widget _premiumMonthNavButton({
    required IconData icon,
    required VoidCallback? onTap,
    required String tooltip,
  }) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Ink(
            height: 48,
            width: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: enabled
                  ? const LinearGradient(
                      colors: AppColors.logoGradient,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    )
                  : null,
              color: enabled ? null : Colors.grey.shade300,
              boxShadow: enabled
                  ? [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.38),
                        blurRadius: 12,
                        offset: const Offset(0, 5),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              icon,
              size: 26,
              color: enabled ? Colors.white : Colors.grey.shade600,
            ),
          ),
        ),
      ),
    );
  }

  int get _viewMonthIndex => _monthIndex(_viewYear, _viewMonth);

  int get _lastDayOfView => DateTime(_viewYear, _viewMonth + 1, 0).day;

  bool get _canPrevMonth => _viewMonthIndex > widget.firstMonthIndex;

  bool get _canNextMonth => _viewMonthIndex < widget.lastMonthIndex;

  @override
  void initState() {
    super.initState();
    _viewYear = widget.year;
    _viewMonth = widget.month;
    _selected = Set<String>.from(widget.initialKeys);
    _holidayKeys = HolidayHelper.nationalHolidayKeysForYear(_viewYear);
  }

  void _shiftMonth(int delta) {
    var y = _viewYear;
    var m = _viewMonth + delta;
    while (m > 12) {
      m -= 12;
      y++;
    }
    while (m < 1) {
      m += 12;
      y--;
    }
    final idx = _monthIndex(y, m);
    if (idx < widget.firstMonthIndex || idx > widget.lastMonthIndex) return;
    setState(() {
      _viewYear = y;
      _viewMonth = m;
      _holidayKeys = HolidayHelper.nationalHolidayKeysForYear(y);
    });
  }

  bool _daySelectable(DateTime dayDt) {
    final n = _normD(dayDt);
    if (widget.selectableMinDay != null && n.isBefore(widget.selectableMinDay!)) {
      return false;
    }
    if (widget.selectableMaxDay != null && n.isAfter(widget.selectableMaxDay!)) {
      return false;
    }
    return true;
  }

  void _toggle(int day) {
    final d = DateTime(_viewYear, _viewMonth, day);
    if (!_daySelectable(d)) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text('Esta data está fora do período permitido.')),
      );
      return;
    }
    final k = _keyD(d);
    setState(() {
      final maxSel = widget.maxSelection;
      if (maxSel == 1) {
        if (_selected.contains(k)) {
          _selected.remove(k);
        } else {
          _selected = {k};
        }
        return;
      }
      if (_selected.contains(k)) {
        _selected.remove(k);
      } else {
        _selected.add(k);
      }
    });
  }

  void _confirmar() {
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Marque ao menos um dia.')),
      );
      return;
    }
    final list = _selected.map((k) {
      final parts = k.split('-');
      final yy = int.parse(parts[0]);
      final mm = int.parse(parts[1]);
      final dd = int.parse(parts[2]);
      return DateTime(yy, mm, dd);
    }).toList()
      ..sort((a, b) => a.compareTo(b));
    Navigator.pop(context, list);
  }

  @override
  Widget build(BuildContext context) {
    final tituloMes =
        DateFormat('MMMM yyyy', 'pt_BR').format(DateTime(_viewYear, _viewMonth, 1));
    final feriadosMes =
        HolidayHelper.getFeriadosDoMes(DateTime(_viewYear, _viewMonth, 1));
    final hoje = DateTime.now();
    final hojeNorm = _normD(hoje);

    final lastDay = _lastDayOfView;
    final firstWeekday = DateTime(_viewYear, _viewMonth, 1).weekday;
    final leadingBlanks = firstWeekday - 1;
    final totalCells = leadingBlanks + lastDay;
    final rowCount = (totalCells / 7).ceil();

    const weekLabels = ['SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SAB', 'DOM'];

    final isSingle = widget.maxSelection == 1;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: AppColors.logoGradient,
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
        ),
        title: Text(
          isSingle ? 'Selecione a data' : 'Selecione a(s) data(s)',
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 0.2,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Fechar',
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () => setState(_selected.clear),
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text(
                'Limpar',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Tamanho dinâmico das células: aproveita largura disponível.
            // Limites: mínimo 44 (toque confortável), máximo 64 (tablet/web).
            final padding = constraints.maxWidth < 380 ? 12.0 : 16.0;
            final cellWidth = (constraints.maxWidth - padding * 2 - 6 * 4) / 7;
            final cellHeight = cellWidth.clamp(46.0, 64.0).toDouble();
            return SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(padding, 12, padding, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Cabeçalho com navegação ◀ mês ▶
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                          color: AppColors.deepBlue.withValues(alpha: 0.10)),
                      boxShadow: [
                        BoxShadow(
                          color:
                              AppColors.deepBlueDark.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _premiumMonthNavButton(
                          icon: Icons.chevron_left_rounded,
                          onTap: _canPrevMonth ? () => _shiftMonth(-1) : null,
                          tooltip: 'Mês anterior',
                        ),
                        Expanded(
                          child: Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            child: Text(
                              tituloMes,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: AppColors.deepBlue,
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ),
                        _premiumMonthNavButton(
                          icon: Icons.chevron_right_rounded,
                          onTap: _canNextMonth ? () => _shiftMonth(1) : null,
                          tooltip: 'Próximo mês',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Calendário
                  Container(
                    padding:
                        const EdgeInsets.fromLTRB(10, 12, 10, 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: AppColors.deepBlue.withValues(alpha: 0.10)),
                      boxShadow: [
                        BoxShadow(
                          color:
                              AppColors.deepBlueDark.withValues(alpha: 0.06),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: weekLabels.asMap().entries.map((e) {
                            final w = e.value;
                            final idx = e.key;
                            final isWeekendCol = idx >= 5;
                            return Expanded(
                              child: Text(
                                w,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isWeekendCol
                                      ? FontWeight.w900
                                      : FontWeight.w800,
                                  color: isWeekendCol
                                      ? _weekendHolidayRed
                                      : Colors.grey.shade700,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 8),
                        for (int r = 0; r < rowCount; r++)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: List.generate(7, (c) {
                                final idx = r * 7 + c;
                                if (idx < leadingBlanks) {
                                  return Expanded(
                                      child: SizedBox(height: cellHeight));
                                }
                                final day = idx - leadingBlanks + 1;
                                if (day > lastDay) {
                                  return Expanded(
                                      child: SizedBox(height: cellHeight));
                                }
                                final dayDt =
                                    DateTime(_viewYear, _viewMonth, day);
                                final k = _keyD(dayDt);
                                final sel = _selected.contains(k);
                                final isToday = _normD(dayDt) == hojeNorm;
                                final isHol = _holidayKeys.contains(k);
                                final isWk = HolidayHelper.isWeekend(dayDt);
                                final redDay = isHol || isWk;
                                final canPick = _daySelectable(dayDt);
                                return Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.all(3),
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: canPick
                                            ? () => _toggle(day)
                                            : null,
                                        borderRadius:
                                            BorderRadius.circular(14),
                                        child: Semantics(
                                          button: true,
                                          label:
                                              'Dia $day de $tituloMes. Toque para ${sel ? 'desmarcar' : 'selecionar'}.',
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 160),
                                            curve: Curves.easeOutCubic,
                                            height: cellHeight,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              gradient: sel
                                                  ? const LinearGradient(
                                                      colors: AppColors
                                                          .logoGradient,
                                                      begin:
                                                          Alignment.topLeft,
                                                      end: Alignment
                                                          .bottomRight,
                                                    )
                                                  : null,
                                              color: sel
                                                  ? null
                                                  : (!canPick
                                                      ? Colors.grey.shade200
                                                      : (isToday
                                                          ? AppColors
                                                              .accent
                                                              .withValues(
                                                                  alpha:
                                                                      0.10)
                                                          : (redDay
                                                              ? _weekendHolidayRed
                                                                  .withValues(
                                                                      alpha:
                                                                          0.10)
                                                              : const Color(
                                                                  0xFFF8FAFC)))),
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              border: Border.all(
                                                color: sel
                                                    ? Colors.transparent
                                                    : (!canPick
                                                        ? Colors
                                                            .grey.shade400
                                                        : (isToday
                                                            ? AppColors
                                                                .accent
                                                            : (redDay
                                                                ? _weekendHolidayRed.withValues(
                                                                    alpha:
                                                                        0.45)
                                                                : Colors
                                                                    .grey
                                                                    .shade200))),
                                                width: sel
                                                    ? 0
                                                    : (isToday ? 2 : 1),
                                              ),
                                              boxShadow: sel
                                                  ? [
                                                      BoxShadow(
                                                        color: AppColors
                                                            .primary
                                                            .withValues(
                                                                alpha: 0.35),
                                                        blurRadius: 8,
                                                        offset: const Offset(
                                                            0, 3),
                                                      ),
                                                    ]
                                                  : null,
                                            ),
                                            child: Text(
                                              '$day',
                                              style: TextStyle(
                                                fontWeight: redDay
                                                    ? FontWeight.w900
                                                    : FontWeight.w800,
                                                fontSize: 18,
                                                color: sel
                                                    ? Colors.white
                                                    : (!canPick
                                                        ? Colors
                                                            .grey.shade500
                                                        : (redDay
                                                            ? _weekendHolidayRed
                                                            : AppColors
                                                                .deepBlue)),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(Icons.info_outline_rounded,
                                size: 14, color: Colors.red.shade700),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'Vermelho/negrito: sábado, domingo e feriados.',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade700,
                                  height: 1.25,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (feriadosMes.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: AppColors.deepBlue
                                .withValues(alpha: 0.10)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.event_note_rounded,
                                  size: 16, color: Colors.red.shade700),
                              const SizedBox(width: 6),
                              Text(
                                'Feriados de $tituloMes',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w900,
                                  color: AppColors.deepBlue,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ...feriadosMes.map((f) => Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '• ',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: _weekendHolidayRed,
                                        height: 1.35,
                                      ),
                                    ),
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          style: TextStyle(
                                            fontSize: 12,
                                            height: 1.35,
                                            color: Colors.grey.shade900,
                                          ),
                                          children: [
                                            TextSpan(
                                              text: DateFormat('dd/MM')
                                                  .format(f.date),
                                              style: TextStyle(
                                                fontWeight: FontWeight.w900,
                                                color: _weekendHolidayRed,
                                              ),
                                            ),
                                            TextSpan(
                                              text: ' — ${f.name}',
                                              style: TextStyle(
                                                fontWeight: f.isOptional
                                                    ? FontWeight.w600
                                                    : FontWeight.w900,
                                                color: f.isOptional
                                                    ? Colors.grey.shade800
                                                    : _weekendHolidayRed,
                                              ),
                                            ),
                                            if (f.isOptional)
                                              TextSpan(
                                                text: ' (facultativo)',
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight:
                                                      FontWeight.w600,
                                                  color:
                                                      Colors.grey.shade600,
                                                  fontStyle:
                                                      FontStyle.italic,
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              )),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(
                  color: AppColors.deepBlue.withValues(alpha: 0.08)),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.deepBlueDark.withValues(alpha: 0.06),
                blurRadius: 14,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_selected.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppColors.accent.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.check_circle_rounded,
                            size: 16, color: AppColors.accent),
                        const SizedBox(width: 6),
                        Text(
                          isSingle
                              ? '1 dia selecionado'
                              : '${_selected.length} dia(s) selecionado(s)',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            color: AppColors.deepBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textSecondary,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Cancelar',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _confirmar,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Confirmar',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding:
                            const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
