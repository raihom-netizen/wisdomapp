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
}
