import 'dart:convert';

import 'widget_event_symbols.dart';

/// Payload nativo v2 — só strings prontas para exibição (Android/iOS desenham, não pensam).
const String kWidgetNativePayloadVersion = '2';
const String kWidgetBrandName = 'WISDOMAPP';
const int _horizonDays = 5;
const int _maxEventsToday = 8;
const int _maxEventsFuture = 6;
const int _titleMaxLen = 42;
const int _financeMaxLen = 64;

const _weekdayNames = <String>[
  '',
  'SEGUNDA-FEIRA',
  'TERÇA-FEIRA',
  'QUARTA-FEIRA',
  'QUINTA-FEIRA',
  'SEXTA-FEIRA',
  'SÁBADO',
  'DOMINGO',
];

const _monthAbbr = <String>[
  'JAN',
  'FEV',
  'MAR',
  'ABR',
  'MAI',
  'JUN',
  'JUL',
  'AGO',
  'SET',
  'OUT',
  'NOV',
  'DEZ',
];

String _truncate(String raw, int maxLen) {
  final s = raw.trim();
  if (s.length <= maxLen) return s;
  if (maxLen <= 1) return s.substring(0, maxLen);
  return '${s.substring(0, maxLen - 1)}…';
}

/// Todo texto exibido no widget nativo em CAIXA ALTA.
String _caps(String raw) => raw.trim().toUpperCase();

String _headerLabelFromMs(int dayMs, {required bool isToday}) {
  final d = DateTime.fromMillisecondsSinceEpoch(dayMs);
  final idx = d.weekday;
  if (idx < 1 || idx > 7) return '';
  final wd = _weekdayNames[idx];
  if (isToday) return wd;
  final month = _monthAbbr[d.month - 1];
  return _caps('$wd, ${d.day} DE $month.');
}

/// Abreviatura para colunas estreitas do widget médio (5 dias).
String _weekdayShortFromMs(int dayMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(dayMs);
  final idx = d.weekday;
  if (idx < 1 || idx > 7) return '';
  final full = _weekdayNames[idx];
  final part = full.split('-').first.trim();
  if (part.length <= 3) return part;
  return part.substring(0, 3);
}

String _formatUpdatedAt(int nowMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final dd = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  final hh = d.hour.toString().padLeft(2, '0');
  final mi = d.minute.toString().padLeft(2, '0');
  return '$dd/$mm $hh:$mi';
}

String _dayOnlyMs(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return DateTime(d.year, d.month, d.day).millisecondsSinceEpoch.toString();
}

String _symbolForType(String type, {String title = ''}) =>
    WidgetEventSymbols.resolve(type: type, title: title);

String _defaultBarColor(
  String type, {
  required bool isToday,
  String symbol = '',
}) =>
    WidgetEventSymbols.defaultBarHex(
      type: type,
      symbol: symbol,
      isToday: isToday,
    );

String _dayNumColor({required bool isToday}) =>
    isToday ? '#FFFF8A50' : '#FFFFFFFF';

Map<String, String> _row({
  required String k,
  String dn = '',
  String wd = '',
  String ws = '',
  String td = '0',
  String dc = '#FFFFFFFF',
  String sy = '',
  String ti = '',
  String tm = '',
  String bc = '#FF00BCD4',
  String tx = '',
  String ag = '',
}) =>
    {
      'k': k,
      if (dn.isNotEmpty) 'dn': dn,
      if (wd.isNotEmpty) 'wd': wd,
      if (ws.isNotEmpty) 'ws': ws,
      if (td.isNotEmpty) 'td': td,
      if (dc.isNotEmpty) 'dc': dc,
      if (sy.isNotEmpty) 'sy': sy,
      if (ti.isNotEmpty) 'ti': ti,
      if (tm.isNotEmpty) 'tm': tm,
      if (bc.isNotEmpty) 'bc': bc,
      if (tx.isNotEmpty) 'tx': tx,
      if (ag.isNotEmpty) 'ag': ag,
    };

/// Entrada serializável para a isolate — eventos já normalizados no Dart principal.
Map<String, dynamic> buildNativeWidgetPayload(Map<String, dynamic> input) {
  final nowMs = input['nowMs'] as int? ?? DateTime.now().millisecondsSinceEpoch;
  final financeRaw = (input['financeRaw'] as String? ?? '').trim();
  final financeItemsRaw = input['financeItems'];
  final financeItems = <Map<String, dynamic>>[];
  if (financeItemsRaw is List) {
    for (final fi in financeItemsRaw) {
      if (fi is Map) financeItems.add(Map<String, dynamic>.from(fi));
    }
  }
  final rawEvents = input['events'];
  final events = <Map<String, dynamic>>[];
  if (rawEvents is List) {
    for (final e in rawEvents) {
      if (e is Map) {
        events.add(Map<String, dynamic>.from(e));
      }
    }
  }

  final todayMs = DateTime.fromMillisecondsSinceEpoch(nowMs);
  final todayStart = DateTime(todayMs.year, todayMs.month, todayMs.day);
  final todayStartMs = todayStart.millisecondsSinceEpoch;

  events.removeWhere((e) {
    final dayMs = int.tryParse('${e['dayMs']}') ?? 0;
    if (dayMs < todayStartMs) return true;
    final untilMs = int.tryParse('${e['visibleUntilMs']}');
    if (untilMs != null && nowMs >= untilMs) return true;
    return false;
  });

  events.sort((a, b) {
    final sa = int.tryParse('${a['sortMs']}') ?? 0;
    final sb = int.tryParse('${b['sortMs']}') ?? 0;
    return sa.compareTo(sb);
  });

  final rows = <Map<String, String>>[];
  var hasAnyEvent = false;

  for (var i = 0; i < _horizonDays; i++) {
    final day = todayStart.add(Duration(days: i));
    final dayMs = day.millisecondsSinceEpoch;
    final dayKey = _dayOnlyMs(dayMs);
    final isToday = i == 0;

    final dayEvents = events.where((e) {
      final eDayMs = int.tryParse('${e['dayMs']}') ?? -1;
      return _dayOnlyMs(eDayMs) == dayKey;
    }).toList();

    rows.add(
      _row(
        k: 'h',
        dn: '${day.day}',
        wd: _headerLabelFromMs(dayMs, isToday: isToday),
        ws: _weekdayShortFromMs(dayMs),
        td: isToday ? '1' : '0',
        dc: _dayNumColor(isToday: isToday),
      ),
    );

    final max = isToday ? _maxEventsToday : _maxEventsFuture;
    final slice = dayEvents.take(max).toList();
    final extra = dayEvents.length - slice.length;

    if (slice.isEmpty) {
      rows.add(_row(
        k: 'x',
        tx: isToday
            ? _caps('Sem compromissos para hoje')
            : _caps('Sem compromissos'),
      ));
    } else {
      for (final e in slice) {
        hasAnyEvent = true;
        final type = (e['type'] ?? 'scale').toString();
        final title = (e['title'] ?? 'Evento').toString();
        final accent = (e['accentHex'] ?? '').toString().trim();
        final symbol =
            (e['symbol'] ?? _symbolForType(type, title: title)).toString();
        rows.add(
          _row(
            k: 'e',
            sy: symbol,
            ti: _caps(_truncate(title, _titleMaxLen)),
            tm: _caps((e['timeRange'] ?? '').toString()),
            bc: accent.isNotEmpty
                ? accent.startsWith('#')
                    ? accent
                    : '#$accent'
                : _defaultBarColor(
                    type,
                    isToday: isToday,
                    symbol: symbol,
                  ),
            ag: type,
          ),
        );
      }
      if (extra > 0) {
        rows.add(_row(k: 'm', tx: _caps('+$extra evento(s)')));
      }
    }
  }

  // Finance rows — prefer new structured list; fallback to legacy financeRaw string.
  final hasFinanceItems = financeItems.isNotEmpty;
  if (hasFinanceItems) {
    for (final fi in financeItems) {
      final sym = (fi['symbol'] ?? '💳').toString();
      final txt =
          _caps(_truncate((fi['text'] ?? '').toString(), _financeMaxLen));
      final bar = (fi['barColor'] ?? '#FFFF8A50').toString();
      if (txt.isNotEmpty) {
        rows.add(_row(k: 'f', sy: sym, tx: txt, bc: bar));
      }
    }
  } else if (financeRaw.isNotEmpty) {
    final parts = financeRaw.split('|');
    final text = _caps(_truncate(parts.first.trim(), _financeMaxLen));
    if (text.isNotEmpty) {
      rows.add(_row(k: 'f', sy: '💳', tx: text, bc: '#FFFF8A50'));
    }
  }

  final hasFinance = hasFinanceItems || financeRaw.isNotEmpty;
  final hint = !hasAnyEvent && !hasFinance
      ? _caps('Sem compromissos para hoje — toque para abrir')
      : _caps('Toque para abrir o WISDOMAPP');

  return {
    'v': kWidgetNativePayloadVersion,
    'rev': nowMs,
    'horizonStartMs': todayStartMs,
    'brand': _caps(kWidgetBrandName),
    'hint': hint,
    'updated': _formatUpdatedAt(nowMs),
    'events': events,
    'financeRaw': hasFinanceItems ? '' : financeRaw,
    'financeItems': financeItems,
    'rows': rows,
  };
}

/// Top-level para [compute] — monta JSON completo fora da UI thread.
String encodeNativeWidgetPayload(Map<String, dynamic> input) {
  return jsonEncode(buildNativeWidgetPayload(input));
}
