import 'package:flutter/material.dart';

/// Data/hora de lançamentos manuais: dia e hora (HH:mm) na UI; Open Finance preserva instante da instituição.
abstract final class FinanceTransactionDatetime {
  FinanceTransactionDatetime._();

  static bool isOpenFinanceBacked(Map<String, dynamic> data) {
    final src = (data['source'] ?? '').toString().trim();
    if (src == 'open_finance') return true;
    final ext = (data['openFinanceExternalId'] ?? '').toString().trim();
    return ext.isNotEmpty;
  }

  /// Combina dia do calendário com hora/minuto escolhidos pelo usuário.
  static DateTime mergeCalendarDayWithTime(DateTime calendarDay, TimeOfDay time) {
    return DateTime(
      calendarDay.year,
      calendarDay.month,
      calendarDay.day,
      time.hour,
      time.minute,
    );
  }

  /// Novo lançamento manual sem hora explícita: dia do calendário + relógio atual.
  static DateTime mergeCalendarDayWithClockNow(DateTime calendarDay) {
    final n = DateTime.now();
    return DateTime(
      calendarDay.year,
      calendarDay.month,
      calendarDay.day,
      n.hour,
      n.minute,
      n.second,
      n.millisecond,
      n.microsecond,
    );
  }

  /// Edição manual: ao mudar só o dia no date picker, mantém hora/min/s do registro anterior.
  static DateTime mergeCalendarDayWithExistingTime(DateTime pickedDay, DateTime previous) {
    return DateTime(
      pickedDay.year,
      pickedDay.month,
      pickedDay.day,
      previous.hour,
      previous.minute,
      previous.second,
      previous.millisecond,
      previous.microsecond,
    );
  }

  /// Normaliza lançamentos manuais para hora/minuto, sem segundos (port CT).
  static DateTime withoutSeconds(DateTime d) {
    return DateTime(d.year, d.month, d.day, d.hour, d.minute);
  }

  /// Se a data veio sem horário (00:00), preenche com o relógio atual; se já
  /// veio com horário escolhido, preserva hora/minuto e remove segundos.
  static DateTime normalizeManualDateTime(DateTime d) {
    final hasClock = d.hour != 0 ||
        d.minute != 0 ||
        d.second != 0 ||
        d.millisecond != 0 ||
        d.microsecond != 0;
    return hasClock ? withoutSeconds(d) : mergeCalendarDayWithClockNow(d);
  }

  /// Dia escolhido + hora/minuto do seletor de horário (port CT).
  static DateTime mergeCalendarDayWithTimeOfDay(
      DateTime pickedDay, int hour, int minute) {
    return DateTime(
        pickedDay.year, pickedDay.month, pickedDay.day, hour, minute);
  }
}
