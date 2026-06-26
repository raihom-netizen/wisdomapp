import 'package:flutter/material.dart' hide showDatePicker;
import 'fast_text_field.dart';
import 'package:flutter/services.dart';
import '../constants/date_time_formats.dart';
import '../theme/app_colors.dart';
import '../utils/date_picker_a11y.dart';

/// Campo de data: calendário (toque) OU digitação manual (dd/MM/yyyy).
/// Use em todo o app onde data é informada.
class DateFieldWithCalendarOrManual extends StatefulWidget {
  final DateTime value;
  final ValueChanged<DateTime> onChanged;
  final DateTime? firstDate;
  final DateTime? lastDate;
  final String? label;
  final bool readOnly;

  const DateFieldWithCalendarOrManual({
    super.key,
    required this.value,
    required this.onChanged,
    this.firstDate,
    this.lastDate,
    this.label,
    this.readOnly = false,
  });

  @override
  State<DateFieldWithCalendarOrManual> createState() => _DateFieldWithCalendarOrManualState();
}

class _DateFieldWithCalendarOrManualState extends State<DateFieldWithCalendarOrManual> {
  late TextEditingController _ctrl;
  String _lastFormatted = '';

  @override
  void initState() {
    super.initState();
    _lastFormatted = DateTimeFormats.dateBR.format(widget.value);
    _ctrl = TextEditingController(text: _lastFormatted);
  }

  @override
  void didUpdateWidget(DateFieldWithCalendarOrManual oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _lastFormatted = DateTimeFormats.dateBR.format(widget.value);
      _ctrl.text = _lastFormatted;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _openCalendar() async {
    if (widget.readOnly) return;
    FocusScope.of(context).unfocus();
    final d = await showDatePicker(
      context: context,
      initialDate: widget.value,
      firstDate: widget.firstDate ?? DateTime(2020),
      lastDate: widget.lastDate ?? DateTime(2030),
    );
    if (d != null) {
      widget.onChanged(d);
      _ctrl.text = DateTimeFormats.dateBR.format(d);
    }
  }

  void _onManualChange(String text) {
    if (text.length == 10 && RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(text)) {
      final parsed = DateTimeFormats.dateBR.parse(text, true);
      if (parsed != null) {
        widget.onChanged(parsed);
        _lastFormatted = text;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: FastTextField(
                controller: _ctrl,
                readOnly: false,
                keyboardType: TextInputType.datetime,
                onTap: widget.readOnly ? null : () => _openCalendar(),
                inputFormatters: [
                  LengthLimitingTextInputFormatter(10),
                  FilteringTextInputFormatter.allow(RegExp(r'[\d/]')),
                  TextInputFormatter.withFunction((old, neu) {
                    final s = neu.text.replaceAll(RegExp(r'\D'), '');
                    if (s.isEmpty) return const TextEditingValue(text: '');
                    if (s.length <= 2) return TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
                    if (s.length <= 4) return TextEditingValue(text: '${s.substring(0, 2)}/${s.substring(2)}', selection: TextSelection.collapsed(offset: s.length + 1));
                    return TextEditingValue(text: '${s.substring(0, 2)}/${s.substring(2, 4)}/${s.substring(4, s.length > 8 ? 8 : s.length)}', selection: TextSelection.collapsed(offset: (s.length > 8 ? 10 : s.length + 2)));
                  }),
                ],
                decoration: InputDecoration(
                  hintText: 'dd/mm/aaaa',
                  prefixIcon: IconButton(
                    icon: Icon(Icons.calendar_today_rounded, color: AppColors.primary, size: 20),
                    onPressed: widget.readOnly ? null : _openCalendar,
                    tooltip: 'Abrir calendário',
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.edit_calendar_rounded, color: Colors.grey.shade600),
                    onPressed: widget.readOnly ? null : _openCalendar,
                    tooltip: 'Abrir calendário',
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: _onManualChange,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Campo de hora: relógio (toque) OU digitação manual (HH:mm).
/// Use em todo o app onde hora é informada.
class TimeFieldWithClockOrManual extends StatefulWidget {
  final TimeOfDay value;
  final ValueChanged<TimeOfDay> onChanged;
  final String? label;
  final bool readOnly;

  const TimeFieldWithClockOrManual({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
    this.readOnly = false,
  });

  @override
  State<TimeFieldWithClockOrManual> createState() => _TimeFieldWithClockOrManualState();
}

class _TimeFieldWithClockOrManualState extends State<TimeFieldWithClockOrManual> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: _format(widget.value));
  }

  @override
  void didUpdateWidget(TimeFieldWithClockOrManual oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != oldWidget.value) {
      _ctrl.text = _format(widget.value);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _format(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  void _openClock() async {
    if (widget.readOnly) return;
    final t = await showTimePicker(
      context: context,
      initialTime: widget.value,
    );
    if (t != null) {
      widget.onChanged(t);
      _ctrl.text = _format(t);
    }
  }

  void _onManualChange(String text) {
    if (RegExp(r'^\d{1,2}:\d{2}$').hasMatch(text) || RegExp(r'^\d{4}$').hasMatch(text)) {
      int h = 0, m = 0;
      if (text.contains(':')) {
        final parts = text.split(':');
        h = int.tryParse(parts[0]) ?? 0;
        m = int.tryParse(parts[1]) ?? 0;
      } else if (text.length == 4) {
        h = int.tryParse(text.substring(0, 2)) ?? 0;
        m = int.tryParse(text.substring(2)) ?? 0;
      }
      if (h >= 0 && h <= 23 && m >= 0 && m <= 59) {
        widget.onChanged(TimeOfDay(hour: h, minute: m));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label != null) ...[
          Text(widget.label!, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: FastTextField(
                controller: _ctrl,
                readOnly: false,
                keyboardType: TextInputType.datetime,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                  TextInputFormatter.withFunction((old, neu) {
                    final s = neu.text.replaceAll(RegExp(r'\D'), '');
                    if (s.isEmpty) return TextEditingValue(text: '');
                    if (s.length <= 2) return TextEditingValue(text: s, selection: TextSelection.collapsed(offset: s.length));
                    return TextEditingValue(text: '${s.substring(0, 2)}:${s.substring(2)}', selection: TextSelection.collapsed(offset: s.length + 1));
                  }),
                ],
                decoration: InputDecoration(
                  hintText: 'HH:mm',
                  prefixIcon: Icon(Icons.access_time_rounded, color: AppColors.primary, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(Icons.schedule_rounded, color: Colors.grey.shade600),
                    onPressed: widget.readOnly ? null : _openClock,
                    tooltip: 'Abrir relógio',
                  ),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  filled: true,
                  fillColor: Colors.white,
                ),
                onChanged: _onManualChange,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
