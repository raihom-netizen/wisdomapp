class HolidayItem {
  final DateTime date;
  final String name;
  final bool isOptional;

  const HolidayItem({
    required this.date,
    required this.name,
    this.isOptional = false,
  });
}

class HolidayHelper {
  /// Chave estável `ano-mês-dia` (sem zero à esquerda), igual ao uso no calendário de escalas.
  static String dateKey(DateTime d) => '${d.year}-${d.month}-${d.day}';

  static Set<String> nationalHolidayKeysForYear(int year) => {
        for (final h in getFeriados(year)) dateKey(h.date),
      };

  static bool isBrazilNationalHoliday(DateTime d) =>
      nationalHolidayKeysForYear(d.year).contains(dateKey(d));

  static bool isWeekend(DateTime d) {
    final w = d.weekday;
    return w == DateTime.saturday || w == DateTime.sunday;
  }

  static DateTime _calculateEaster(int year) {
    // Algoritmo de Meeus/Jones/Butcher para calendário gregoriano.
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  static List<HolidayItem> getFeriados(int year) {
    final easter = _calculateEaster(year);
    final holidays = <HolidayItem>[
      HolidayItem(date: DateTime(year, 1, 1), name: 'Confraternizacao Universal'),
      HolidayItem(date: DateTime(year, 4, 21), name: 'Tiradentes'),
      HolidayItem(date: DateTime(year, 5, 1), name: 'Dia do Trabalhador'),
      HolidayItem(date: DateTime(year, 9, 7), name: 'Independencia do Brasil'),
      HolidayItem(date: DateTime(year, 10, 12), name: 'Nossa Senhora Aparecida'),
      HolidayItem(date: DateTime(year, 11, 2), name: 'Finados'),
      HolidayItem(date: DateTime(year, 11, 15), name: 'Proclamacao da Republica'),
      HolidayItem(date: DateTime(year, 11, 20), name: 'Consciencia Negra'),
      HolidayItem(date: DateTime(year, 12, 25), name: 'Natal'),
      HolidayItem(
        date: easter.subtract(const Duration(days: 47)),
        name: 'Carnaval',
        isOptional: true,
      ),
      HolidayItem(
        date: easter.subtract(const Duration(days: 2)),
        name: 'Paixao de Cristo',
      ),
      HolidayItem(
        date: easter.add(const Duration(days: 60)),
        name: 'Corpus Christi',
        isOptional: true,
      ),
    ];

    holidays.sort((a, b) => a.date.compareTo(b.date));
    return holidays;
  }

  static List<HolidayItem> getFeriadosDoMes(DateTime referenceDate) {
    final all = getFeriados(referenceDate.year);
    final month = referenceDate.month;
    return all.where((h) => h.date.month == month).toList();
  }
}
