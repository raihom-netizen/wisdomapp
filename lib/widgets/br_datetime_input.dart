import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../constants/date_time_formats.dart';
import 'fast_text_field.dart';

/// Converte texto dd/MM/yyyy → [DateTime] (só calendário).
DateTime? parseBrDateInput(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  for (final pattern in ['dd/MM/yyyy', 'dd/MM/yy', 'd/M/yyyy', 'd/M/yy']) {
    try {
      return DateFormat(pattern, 'pt_BR').parseStrict(t);
    } catch (_) {}
  }
  return null;
}

/// Converte texto HH:mm:ss ou HH:mm → hora/minuto/segundo.
({int hour, int minute, int second})? parseBrTimeInput(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final parts = t.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]) ?? -1;
  final m = int.tryParse(parts[1]) ?? -1;
  final s = parts.length >= 3 ? (int.tryParse(parts[2]) ?? 0) : 0;
  if (h < 0 || h > 23 || m < 0 || m > 59 || s < 0 || s > 59) return null;
  return (hour: h, minute: m, second: s);
}

DateTime? combineBrDateAndTime(String dateRaw, String timeRaw) {
  final d = parseBrDateInput(dateRaw);
  if (d == null) return null;
  final tm = parseBrTimeInput(timeRaw);
  if (tm == null) {
    return DateTime(d.year, d.month, d.day);
  }
  return DateTime(d.year, d.month, d.day, tm.hour, tm.minute, tm.second);
}

void syncBrDateTimeControllers(DateTime dt, TextEditingController dateCtrl, TextEditingController timeCtrl) {
  dateCtrl.text = DateTimeFormats.formatDate(dt);
  timeCtrl.text = DateTimeFormats.time24Seconds.format(dt);
}

/// Máscara dd/MM/yyyy enquanto digita.
class BrDateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }
    final b = StringBuffer();
    for (var i = 0; i < digits.length && i < 8; i++) {
      if (i == 2 || i == 4) b.write('/');
      b.write(digits[i]);
    }
    final text = b.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Máscara HH:mm:ss (24h) enquanto digita.
class BrTimeInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }
    final b = StringBuffer();
    for (var i = 0; i < digits.length && i < 6; i++) {
      if (i == 2 || i == 4) b.write(':');
      b.write(digits[i]);
    }
    final text = b.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Campo data padrão BR (dd/MM/yyyy).
class BrDateTextField extends StatelessWidget {
  const BrDateTextField({
    super.key,
    required this.controller,
    this.labelText = 'Data',
    this.onChanged,
  });

  final TextEditingController controller;
  final String labelText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return FastTextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [BrDateInputFormatter()],
      decoration: InputDecoration(
        labelText: labelText,
        hintText: 'dd/mm/aaaa',
        prefixIcon: const Icon(Icons.calendar_today_rounded, size: 20),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
      ),
      onChanged: onChanged,
    );
  }
}

/// Campo hora padrão BR 24h (HH:mm:ss).
class BrTimeTextField extends StatelessWidget {
  const BrTimeTextField({
    super.key,
    required this.controller,
    this.labelText = 'Hora',
    this.onChanged,
  });

  final TextEditingController controller;
  final String labelText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return FastTextField(
      controller: controller,
      keyboardType: TextInputType.number,
      inputFormatters: [BrTimeInputFormatter()],
      decoration: InputDecoration(
        labelText: labelText,
        hintText: 'hh:mm:ss',
        prefixIcon: const Icon(Icons.schedule_rounded, size: 20),
        border: const OutlineInputBorder(),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
      ),
      onChanged: onChanged,
    );
  }
}
