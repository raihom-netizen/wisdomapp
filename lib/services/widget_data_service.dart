import 'package:flutter/foundation.dart'
    show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:home_widget/home_widget.dart';

import '../models/scale_entry.dart';
import '../theme/app_colors.dart';
import '../utils/firestore_user_doc_id.dart';

/// Dados para o widget da tela inicial (**só Android**): **apenas Escalas** — calendário do mês + próximo plantão.
/// iOS: não chama `home_widget`.
class WidgetDataService {
  WidgetDataService._();

  /// Nome do provider Android (classe Kotlin registrada no AndroidManifest).
  static const String androidName = 'ControleTotalWidgetProvider';
  static const Duration _minUpdateGap = Duration(minutes: 15);
  static Future<void>? _updateFuture;
  static DateTime? _lastUpdateAt;

  static String _argbHex(Color c) {
    // ignore: deprecated_member_use
    return c.value.toRadixString(16).padLeft(8, '0');
  }

  static String _cell(
    int day,
    bool today,
    Color bg,
    Color fg,
    int dots,
  ) {
    return '${day == 0 ? 0 : day},${today ? 1 : 0},${_argbHex(bg)},${_argbHex(fg)},$dots';
  }

  static Future<String> _monthCalendarPayload(String fsUid) async {
    try {
      final now = DateTime.now();
      final y = now.year;
      final m = now.month;
      final monthStart = DateTime(y, m, 1);
      final monthEnd = DateTime(y, m + 1, 0, 23, 59, 59);

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(fsUid)
          .collection('scales')
          .where('date',
              isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('date',
              isLessThanOrEqualTo: Timestamp.fromDate(monthEnd))
          .get(const GetOptions(source: Source.serverAndCache));

      final byDay = <DateTime, List<ScaleEntry>>{};
      for (final doc in snap.docs) {
        final d = doc.data();
        if (d['isAgendaMirror'] == true ||
            d['isProdutividadeFolgaMirror'] == true) {
          continue;
        }
        final e = ScaleEntry.fromDoc(doc);
        final key = DateTime(e.date.year, e.date.month, e.date.day);
        byDay.putIfAbsent(key, () => []).add(e);
      }

      final last = DateTime(y, m + 1, 0);
      // Segunda = primeira coluna (mesmo padrão do TableCalendar no app).
      final lead = (monthStart.weekday + 6) % 7;
      final parts = <String>[];

      for (var i = 0; i < 42; i++) {
        final dayNum = i - lead + 1;
        if (dayNum < 1 || dayNum > last.day) {
          parts.add(_cell(0, false, const Color(0xFFF8FAFC),
              const Color(0xFF94A3B8), 0));
          continue;
        }
        final d = DateTime(y, m, dayNum);
        final list = byDay[DateTime(d.year, d.month, d.day)] ?? [];
        final isToday = d.year == now.year &&
            d.month == now.month &&
            d.day == now.day;
        final weekend = d.weekday == DateTime.saturday ||
            d.weekday == DateTime.sunday;

        if (list.isEmpty) {
          final fg = weekend
              ? const Color(0xFFE53935)
              : const Color(0xFF1A1C1E);
          parts.add(_cell(dayNum, isToday, const Color(0xFFF8FAFC), fg, 0));
        } else {
          final fill = AppColors.vividShift(list.first.color);
          final fg = AppColors.onVividFill(fill);
          parts.add(_cell(dayNum, isToday, fill, fg, list.length));
        }
      }
      return parts.join(';');
    } catch (_) {
      return List<String>.filled(42, _cell(0, false, const Color(0xFFF8FAFC),
              const Color(0xFF94A3B8), 0))
          .join(';');
    }
  }

  /// Atualiza o widget (calendário Escalas + próximo plantão). Chamar ao entrar no HomeShell. Web: noop. iOS: noop.
  static Future<void> updateWidgetData(String authUid) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final now = DateTime.now();
    if (_lastUpdateAt != null && now.difference(_lastUpdateAt!) < _minUpdateGap) {
      return;
    }
    final inFlight = _updateFuture;
    if (inFlight != null) return inFlight;
    _updateFuture = _updateWidgetDataNow(authUid).whenComplete(() {
      _updateFuture = null;
    });
    return _updateFuture!;
  }

  static Future<void> _updateWidgetDataNow(String authUid) async {
    try {
      final fsUid = firestoreUserDocIdForAppShell(authUid);
      final nextScaleFuture = _fetchNextScale(fsUid);
      final calPayloadFuture = _monthCalendarPayload(fsUid);
      final rawTitle =
          DateFormat.yMMMM('pt_BR').format(DateTime.now());
      final calTitle = rawTitle.isEmpty
          ? 'Escalas'
          : '${rawTitle[0].toUpperCase()}${rawTitle.substring(1)}';
      final nextScale = await nextScaleFuture;
      final calPayload = await calPayloadFuture;

      await HomeWidget.saveWidgetData<String>('next_scale_date', nextScale.$1);
      await HomeWidget.saveWidgetData<String>('next_scale_label', nextScale.$2);
      await HomeWidget.saveWidgetData<String>('next_scale_time', nextScale.$3);
      await HomeWidget.saveWidgetData<String>('widget_cal_title', calTitle);
      await HomeWidget.saveWidgetData<String>('widget_cal_payload', calPayload);

      await HomeWidget.updateWidget(name: androidName);
      _lastUpdateAt = DateTime.now();
    } catch (_) {}
  }

  /// (dateStr, label, timeStr)
  static Future<(String, String, String)> _fetchNextScale(String fsUid) async {
    try {
      final now = DateTime.now();
      final startOfToday = DateTime(now.year, now.month, now.day);
      final endOfRange = startOfToday.add(const Duration(days: 90));

      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(fsUid)
          .collection('scales')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfRange))
          .orderBy('date')
          .limit(10)
          .get(const GetOptions(source: Source.serverAndCache));

      final docs = snap.docs
          .where((d) =>
              d.data()['isAgendaMirror'] != true &&
              d.data()['isProdutividadeFolgaMirror'] != true)
          .toList();
      if (docs.isEmpty) {
        return ('', 'Nenhum plantão em breve', '');
      }

      final doc = docs.first;
      final d = doc.data();
      final date = (d['date'] as Timestamp?)?.toDate();
      final start = (d['start'] ?? '').toString();
      final label =
          (d['label'] ?? d['abbreviation'] ?? 'Plantão').toString().trim();
      if (label.isEmpty) {
        return (date != null ? DateFormat('dd/MM').format(date) : '', 'Plantão', start);
      }

      return (
        date != null ? DateFormat('dd/MM').format(date) : '',
        label,
        start,
      );
    } catch (_) {
      return ('', 'Não disponível', '');
    }
  }
}
