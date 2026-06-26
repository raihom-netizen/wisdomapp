import 'package:intl/intl.dart';

/// Padrão brasileiro: data dd/MM/yyyy e hora 24h (HH:mm).
/// Use em todo o app para exibição e parsing.
class DateTimeFormats {
  DateTimeFormats._();

  static final DateFormat dateBR = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final DateFormat time24 = DateFormat('HH:mm', 'pt_BR');
  static final DateFormat time24Seconds = DateFormat('HH:mm:ss', 'pt_BR');
  static final DateFormat dateTimeBR = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  static final DateFormat dateTimeSecondsBR =
      DateFormat('dd/MM/yyyy HH:mm:ss', 'pt_BR');

  static String formatDate(DateTime d) => dateBR.format(d);
  /// Hora no formato 24h (ex: 14:30).
  static String formatTime(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// Data e hora brasileira com segundos (ex: 18/06/2026 12:28:35).
  static String formatDateTimeSeconds(DateTime d) => dateTimeSecondsBR.format(d);

  /// Só hora e minuto (ex: 14:30) — use nas grids com cabeçalho de dia.
  static String formatTimeOnly(DateTime d) => time24.format(d);
}
