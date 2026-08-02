import 'dart:async';

import 'dart:convert';

import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show compute, kIsWeb, defaultTargetPlatform, TargetPlatform;

import 'package:flutter/material.dart';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:home_widget/home_widget.dart';

import '../constants/currency_formats.dart';

import '../models/finance_account.dart';

import '../models/scale_entry.dart';

import '../theme/app_colors.dart';
import '../constants/commitment_presets.dart';

import '../utils/agenda_reminder_end_of_day.dart';

import '../utils/agenda_reminder_module_scope.dart';

import '../utils/firestore_user_doc_id.dart';

import 'widget_event_symbols.dart';

import '../utils/connectivity_offline.dart';
import '../utils/widget_scale_visibility.dart';

import 'widget_native_payload_builder.dart';

import 'widget_native_payload_cache.dart';

import 'widget_last_sync_prefs.dart';
import 'widget_firestore_live_sync.dart';
import 'widget_native_platform_sync.dart';
import 'widget_android_alarm_sync.dart';

/// Evento interno — convertido para mapa serializável antes da isolate.

class WidgetDayEvent {
  const WidgetDayEvent({
    required this.day,
    required this.sortAt,
    required this.type,
    required this.title,
    required this.timeRange,
    this.accentHex,
    this.symbol,
    this.visibleUntil,
  });

  final DateTime day;

  final DateTime sortAt;

  final String type;

  final String title;

  final String timeRange;

  final String? accentHex;

  final String? symbol;

  final DateTime? visibleUntil;

  Map<String, dynamic> toIsolateMap() => {
        'dayMs': day.millisecondsSinceEpoch,
        'sortMs': sortAt.millisecondsSinceEpoch,
        'type': type,
        'title': title,
        'timeRange': timeRange,
        'symbol':
            symbol ?? WidgetEventSymbols.resolve(type: type, title: title),
        if (accentHex != null && accentHex!.isNotEmpty) 'accentHex': accentHex,
        if (visibleUntil != null)
          'visibleUntilMs': visibleUntil!.millisecondsSinceEpoch,
      };
}

/// Ponte Flutter → widget nativo (home_widget): Firestore → isolate → JSON mastigado.

class WidgetUpdateService {
  WidgetUpdateService._();

  static const String androidName = 'ControleTotalWidgetProvider';

  static const String androidSmallName = 'ControleTotalWidgetSmallProvider';

  static const String androidMediumName = 'ControleTotalWidgetMediumProvider';

  static const String iosName = 'ControleTotalWidget';

  static const String appGroupId = 'group.com.wisdomapp.app.widget';

  static const String jsonKey = 'widget_events_json';

  static const List<String> _legacyWidgetKeys = [
    'widget_days_json',
    'widget_calendar_days',
    'widget_events_legacy',
    'widget_past_days',
    'widget_db_days',
    'widget_events_v0',
    'widget_events_v1',
    'widget_db_brand',
    'widget_db_hint',
    'widget_db_updated',
  ];

  static const int _horizonDays = 5;

  static const int _queryLimit = 28;

  static Future<void>? _updateFuture;

  static DateTime? _lastUpdateAt;

  static bool _appGroupConfigured = false;

  static String? _lastJsonPayload;

  static bool _payloadStale = false;

  static String? _pendingForceUid;

  static bool _legacyStoragePurged = false;

  static Timer? _widgetFollowUpTimer;

  static DateTime? _lastForegroundRefreshAt;

  /// Resume/foreground: refresh leve só se necessário (evita rajada).
  static const Duration _foregroundRefreshMinGap = Duration(seconds: 60);

  static String symbolForType(
    String type, {
    String title = '',
    String abbreviation = '',
  }) =>
      WidgetEventSymbols.resolve(
        type: type,
        title: title,
        abbreviation: abbreviation,
      );

  static DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  static Future<bool> _networkLikelyAvailable() async {
    try {
      return !isConnectivityOffline(await Connectivity().checkConnectivity());
    } catch (_) {
      return false;
    }
  }

  /// Cache local primeiro — widget não depende de rede para pintar.
  static Future<QuerySnapshot<Map<String, dynamic>>> _cacheFirstQueryGet(
    Query<Map<String, dynamic>> query, {
    bool tryServerIfCacheEmpty = false,
    bool preferServerWhenOnline = false,
    bool cacheOnly = false,
  }) async {
    if (cacheOnly) {
      try {
        return await query.get(const GetOptions(source: Source.cache));
      } catch (_) {
        return await query.get();
      }
    }

    if (preferServerWhenOnline && await _networkLikelyAvailable()) {
      try {
        return await query
            .get(const GetOptions(source: Source.serverAndCache))
            .timeout(const Duration(seconds: 6));
      } catch (_) {
        // Cai no cache abaixo.
      }
    }

    try {
      final cached = await query.get(const GetOptions(source: Source.cache));
      if (cached.docs.isNotEmpty || !tryServerIfCacheEmpty) return cached;
    } catch (_) {
      if (!tryServerIfCacheEmpty) rethrow;
    }

    try {
      return await query
          .get(const GetOptions(source: Source.serverAndCache))
          .timeout(const Duration(seconds: 4));
    } catch (_) {
      return await query.get(const GetOptions(source: Source.cache));
    }
  }

  static bool _scaleCompromissoVisibleOnWidget(ScaleEntry e, DateTime now) {
    final isComp = e.isAgendaMirror || e.isCompromissoParticularEfetivo;
    return scaleEntryVisibleOnWidget(
      startHHmm: e.start,
      endHHmm: e.end,
      day: _dayOnly(e.date),
      now: now,
      isCompromissoOrMirror: isComp,
    );
  }

  static String _timeRange(String start, String end) {
    final s = start.trim();

    final e = end.trim();

    if (s.isEmpty && e.isEmpty) return '';

    if (e.isEmpty) return s;

    if (s.isEmpty) return e;

    return '$s-$e';
  }

  static String _accentHex(Color c) {
    // ignore: deprecated_member_use
    return '#${c.value.toRadixString(16).padLeft(8, '0').toUpperCase()}';
  }

  static String _scaleTitle(ScaleEntry e) {
    if (e.isAgendaMirror || e.isCompromissoParticularEfetivo) {
      final lbl = stripLeadingCompromissoWord((e.label ?? '').trim());
      return lbl.isNotEmpty ? lbl : 'Compromisso';
    }

    final lbl = (e.label ?? '').trim();
    final abbr = (e.abbreviation ?? '').trim();
    if (lbl.isNotEmpty) return lbl;
    if (abbr.isNotEmpty) return abbr;
    return 'Plantão';
  }

  static String _scaleType(ScaleEntry e) {
    if (e.isAgendaMirror || e.isCompromissoParticularEfetivo) {
      return 'compromisso';
    }
    return 'scale';
  }

  static Color _accentForType(String type, {required bool isToday}) {
    switch (type) {
      case 'compromisso':
        return const Color(0xFF12B5A5);
      case 'finance':
        return const Color(0xFFFF8A50);
      default:
        return isToday ? const Color(0xFF00BCD4) : const Color(0xFFFFC107);
    }
  }

  static DateTime? _sortFromScale(ScaleEntry e) {
    final parts = e.start.split(':');

    final h = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;

    final m = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;

    return DateTime(e.date.year, e.date.month, e.date.day, h, m);
  }

  static WidgetDayEvent? _eventFromScale(ScaleEntry e,
      {required bool isToday}) {
    if (!_scaleCompromissoVisibleOnWidget(e, DateTime.now())) return null;

    final type = _scaleType(e);

    final sortAt = _sortFromScale(e) ?? _dayOnly(e.date);

    final title = _scaleTitle(e);
    final isComp = e.isAgendaMirror || e.isCompromissoParticularEfetivo;
    final visibleUntil = scaleEntryWidgetVisibleUntil(
      startHHmm: e.start,
      endHHmm: e.end,
      day: _dayOnly(e.date),
      isCompromissoOrMirror: isComp,
    );
    final Color accent;
    if (type == 'compromisso') {
      accent = resolveCommitmentVisual(title).color;
    } else if (e.isAgendaMirror || e.isCompromissoParticularEfetivo) {
      accent = _accentForType(type, isToday: isToday);
    } else {
      accent = AppColors.vividShift(e.color);
    }
    return WidgetDayEvent(
      day: _dayOnly(e.date),
      sortAt: sortAt,
      type: type,
      title: title,
      timeRange: _timeRange(e.start, e.end),
      accentHex: _accentHex(accent),
      symbol: WidgetEventSymbols.resolve(
        type: type,
        title: title,
        abbreviation: (e.abbreviation ?? '').trim(),
      ),
      visibleUntil: visibleUntil,
    );
  }

  static WidgetDayEvent? _eventFromReminder(
    Map<String, dynamic> d, {
    required bool isToday,
  }) {
    if (!agendaReminderBelongsInAgendaModule(d)) return null;

    final now = DateTime.now();

    if (!agendaReminderVisibleOnWidget(d, now)) return null;

    final day = _dayOnly((d['date'] as Timestamp).toDate());

    const type = 'compromisso';

    final titleRaw = (d['title'] ?? d['label'] ?? '').toString().trim();

    final clean = stripLeadingCompromissoWord(titleRaw);
    final title = clean.isNotEmpty ? clean : 'Compromisso';

    final start = (d['time'] ?? d['start'] ?? '').toString();

    final end = (d['endTime'] ?? d['end'] ?? '').toString();

    final sortAt = agendaReminderEventStartDateTime(d) ?? day;
    final endAt = agendaReminderEventEndDateTime(d);
    final visibleUntil = endAt != null
        ? endAt.add(kWidgetCompromissoGraceAfterEnd)
        : day.add(const Duration(days: 1));

    return WidgetDayEvent(
      day: day,
      sortAt: sortAt,
      type: type,
      title: title,
      timeRange: _timeRange(start, end),
      accentHex: _accentHex(
        type == 'compromisso'
            ? resolveCommitmentVisual(title).color
            : _accentForType(type, isToday: isToday),
      ),
      symbol: WidgetEventSymbols.resolve(type: type, title: title),
      visibleUntil: visibleUntil,
    );
  }

  static Future<List<WidgetDayEvent>> _fetchScaleEvents(
    String fsUid, {
    bool preferCache = false,
    bool bypassThrottle = false,
  }) async {
    try {
      final now = DateTime.now();
      final start = _dayOnly(now);
      final end = start.add(Duration(days: _horizonDays - 1));
      final endInclusive = DateTime(end.year, end.month, end.day, 23, 59, 59);

      // Pós-salvar: cache local Firestore (já reflete write/delete) — nunca servidor.
      final cacheOnly = preferCache || bypassThrottle;

      final query = FirebaseFirestore.instance
          .collection('users')
          .doc(fsUid)
          .collection('scales')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endInclusive))
          .limit(_queryLimit);

      final snap = await _cacheFirstQueryGet(
        query,
        tryServerIfCacheEmpty: !cacheOnly,
        preferServerWhenOnline: !cacheOnly,
        cacheOnly: cacheOnly,
      );

      final out = <WidgetDayEvent>[];

      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['isProdutividadeFolgaMirror'] == true) continue;
        final e = ScaleEntry.fromDoc(doc);
        final isToday = _dayOnly(e.date) == start;
        final ev = _eventFromScale(e, isToday: isToday);
        if (ev != null) out.add(ev);
      }

      return _dedupeScaleEvents(out);
    } catch (_) {
      return [];
    }
  }

  static List<WidgetDayEvent> _dedupeScaleEvents(List<WidgetDayEvent> events) {
    final merged = <String, WidgetDayEvent>{};
    for (final e in events) {
      final key =
          '${e.day.millisecondsSinceEpoch}|${e.type}|${e.title}|${e.timeRange}';
      merged[key] = e;
    }
    return merged.values.toList();
  }

  static Future<List<WidgetDayEvent>> _fetchReminderEvents(
    String fsUid, {
    bool preferCache = false,
    bool bypassThrottle = false,
  }) async {
    try {
      final now = DateTime.now();

      final start = _dayOnly(now);

      final end = start.add(Duration(days: _horizonDays - 1));

      final endInclusive = DateTime(end.year, end.month, end.day, 23, 59, 59);

      final cacheOnly = preferCache || bypassThrottle;

      final query = FirebaseFirestore.instance
          .collection('users')
          .doc(fsUid)
          .collection('reminders')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endInclusive))
          .limit(_queryLimit);

      final snap = await _cacheFirstQueryGet(
        query,
        tryServerIfCacheEmpty: !cacheOnly,
        preferServerWhenOnline: !cacheOnly,
        cacheOnly: cacheOnly,
      );

      final out = <WidgetDayEvent>[];

      for (final doc in snap.docs) {
        final isToday =
            _dayOnly((doc.data()['date'] as Timestamp).toDate()) == start;

        final ev = _eventFromReminder(doc.data(), isToday: isToday);

        if (ev != null) out.add(ev);
      }

      return out;
    } catch (_) {
      return [];
    }
  }

  static List<WidgetDayEvent> _mergeEvents(
    List<WidgetDayEvent> scales,
    List<WidgetDayEvent> reminders, [
    List<WidgetDayEvent> financeEvents = const [],
  ]) {
    final today = _dayOnly(DateTime.now());

    final merged = <String, WidgetDayEvent>{};

    for (final e in [...scales, ...reminders, ...financeEvents]) {
      if (e.day.isBefore(today)) continue;

      final key =
          '${e.day.millisecondsSinceEpoch}|${e.type}|${e.title}|${e.timeRange}';

      merged[key] = e;
    }

    return merged.values.toList();
  }

  /// Busca despesas e receitas pendentes no horizonte do widget (5 dias).
  /// Retorna como WidgetDayEvent para aparecer na grade diária com ícones modernos.
  static Future<List<WidgetDayEvent>> _fetchFinancePendingAsEvents(
    String fsUid, {
    bool preferCache = false,
    bool bypassThrottle = false,
  }) async {
    try {
      final now = DateTime.now();
      final start = _dayOnly(now);
      final end = start.add(Duration(days: _horizonDays - 1));
      final endInclusive = DateTime(end.year, end.month, end.day, 23, 59, 59);
      final cacheOnly = preferCache || bypassThrottle;

      final ccIds = await _fetchCreditCardIds(fsUid);

      final col = FirebaseFirestore.instance
          .collection('users')
          .doc(fsUid)
          .collection('transactions');

      final out = <WidgetDayEvent>[];

      for (final type in const ['expense', 'income']) {
        final docs = await _queryPendingInRange(
          col: col,
          type: type,
          start: start,
          endInclusive: endInclusive,
          cacheOnly: cacheOnly,
        );

        final isExpense = type == 'expense';

        for (final doc in docs) {
          final d = doc.data();
          final amount = (d['amount'] ?? 0).toDouble().abs();
          final accountId = (d['financeAccountId'] ?? '').toString().trim();
          final isCc = ccIds.isNotEmpty && accountId.isNotEmpty && ccIds.contains(accountId);

          final desc = (d['description'] ?? '').toString().trim();
          final category = (d['category'] ?? '').toString().trim();

          final String title;
          final String symbol;
          final String accentHex;

          if (isCc) {
            final label = desc.isNotEmpty ? desc : (category.isNotEmpty ? category : 'Fatura Cartão');
            title = '$label · ${CurrencyFormats.formatBRL(amount)}';
            symbol = '💳';
            accentHex = '#FFFBBF24';
          } else if (isExpense) {
            final label = desc.isNotEmpty ? desc : (category.isNotEmpty ? category : 'Despesa');
            title = '$label · ${CurrencyFormats.formatBRL(amount)}';
            symbol = '📉';
            accentHex = '#FFFF5252';
          } else {
            final label = desc.isNotEmpty ? desc : (category.isNotEmpty ? category : 'Receita');
            title = '$label · ${CurrencyFormats.formatBRL(amount)}';
            symbol = '📈';
            accentHex = '#FF4CAF50';
          }

          final ts = d['date'];
          final DateTime txDate;
          if (ts is Timestamp) {
            txDate = _dayOnly(ts.toDate());
          } else {
            continue;
          }

          out.add(WidgetDayEvent(
            day: txDate,
            sortAt: txDate,
            type: type,
            title: title,
            timeRange: '',
            accentHex: accentHex,
            symbol: symbol,
          ));
        }
      }

      return out;
    } catch (_) {
      return const [];
    }
  }

  /// Query auxiliar: busca transações pendentes no intervalo de datas.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _queryPendingInRange({
    required CollectionReference<Map<String, dynamic>> col,
    required String type,
    required DateTime start,
    required DateTime endInclusive,
    required bool cacheOnly,
  }) async {
    final merged = <String, QueryDocumentSnapshot<Map<String, dynamic>>>{};
    for (final field in const ['date', 'effectiveDate']) {
      try {
        final query = col
            .where(field, isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where(field, isLessThanOrEqualTo: Timestamp.fromDate(endInclusive))
            .where('status', isEqualTo: 'pending')
            .where('type', isEqualTo: type)
            .orderBy(field, descending: false)
            .limit(180);
        final snap = await _cacheFirstQueryGet(
          query,
          tryServerIfCacheEmpty: !cacheOnly,
          preferServerWhenOnline: !cacheOnly,
          cacheOnly: cacheOnly,
        );
        for (final doc in snap.docs) {
          merged[doc.id] = doc;
        }
      } catch (_) {}
    }
    return merged.values.toList(growable: false);
  }

  static Future<Set<String>> _fetchCreditCardIds(String fsUid) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(fsUid)
          .collection('finance_accounts')
          .limit(100)
          .get(const GetOptions(source: Source.cache));
      final ids = <String>{};
      for (final doc in snap.docs) {
        final acc = FinanceAccount.fromDoc(doc);
        if (acc.isCreditCardProduct) ids.add(acc.id);
      }
      return ids;
    } catch (_) {
      return const <String>{};
    }
  }

  static Future<void> _ensureAppGroup() async {
    if (_appGroupConfigured || kIsWeb) return;

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        await HomeWidget.setAppGroupId(appGroupId);

        _appGroupConfigured = true;
      } catch (_) {}
    }
  }

  static Future<void> syncOpenModuleIndex(int moduleIndex) async {
    if (!_isNativeMobile) return;

    if (moduleIndex < 0 || moduleIndex > 9) return;

    try {
      await _ensureAppGroup();

      await HomeWidget.saveWidgetData<int>('widget_open_module', moduleIndex);
    } catch (_) {}
  }

  static Future<void> configureNativeBridge() async {
    await _ensureAppGroup();
  }

  /// Escuta Firestore local (scales + reminders) e refresh imediato ao criar/remover.
  static void configurePeriodicLocalRefresh(
    String authUid, {
    bool runNow = false,
  }) {
    if (!_isNativeMobile && !kIsWeb) return;
    final cleanUid = authUid.trim();
    if (cleanUid.isEmpty) {
      stopPeriodicLocalRefresh();
      return;
    }
    WidgetFirestoreLiveSync.bind(cleanUid);
    unawaited(WidgetAndroidAlarmSync.scheduleAlarmsIfNeeded());
    if (runNow) {
      scheduleWidgetRefresh(cleanUid);
    }
  }

  /// App aberto / resume: reanexa listeners; refresh só se pendente ou intervalo mínimo.
  static void keepAliveWhileForeground(String authUid) {
    if (authUid.isEmpty) return;
    if (!_isNativeMobile && !kIsWeb) return;
    unawaited(() async {
      final alarmDue = await WidgetAndroidAlarmSync.consumeNativeSyncDue();
      if (alarmDue) {
        scheduleWidgetRefresh(authUid);
      }
    }());
    WidgetFirestoreLiveSync.rebindIfHorizonStale(authUid);
    WidgetFirestoreLiveSync.bind(authUid);
    if (_payloadStale) {
      scheduleWidgetRefresh(authUid);
      return;
    }
    final now = DateTime.now();
    final last = _lastForegroundRefreshAt;
    if (last != null && now.difference(last) < _foregroundRefreshMinGap) {
      return;
    }
    _lastForegroundRefreshAt = now;
    unawaited(_refreshNow(authUid, preferCache: true, bypassThrottle: true));
  }

  static void stopPeriodicLocalRefresh() {
    _widgetFollowUpTimer?.cancel();
    _widgetFollowUpTimer = null;
    WidgetFirestoreLiveSync.unbind();
  }

  static bool get _isNativeMobile {
    if (kIsWeb) return false;

    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
  }

  static Future<void> updateWidgetData(String authUid) async {
    if (authUid.isEmpty) return;
    if (!_isNativeMobile && !kIsWeb) return;

    configurePeriodicLocalRefresh(authUid);
    scheduleWidgetRefresh(authUid);
  }

  static Future<void> _purgeLegacyWidgetStorage() async {
    if (_legacyStoragePurged || !_isNativeMobile) return;

    _legacyStoragePurged = true;

    for (final key in _legacyWidgetKeys) {
      try {
        await HomeWidget.saveWidgetData<String>(key, '');
      } catch (_) {}
    }
  }

  static Future<void> _persistNativeWidget(String jsonStr) async {
    await _purgeLegacyWidgetStorage();
    try {
      // Nativo primeiro (commit + redraw iOS/Android) — caminho crítico do widget.
      await WidgetNativePlatformSync.afterWidgetJsonSaved(jsonStr);
      unawaited(WidgetAndroidAlarmSync.scheduleAlarmsIfNeeded());
      unawaited(_scheduleNextPlantaoExpiryAlarm(jsonStr));
      // Plugin home_widget em paralelo (compat); não bloqueia redraw nativo.
      unawaited(
        HomeWidget.saveWidgetData<String>(jsonKey, jsonStr)
            .catchError((_) => false),
      );
    } catch (_) {}
  }

  /// Android: alarme no fim + 2h do plantão para limpar widget com app fechado.
  static Future<void> _scheduleNextPlantaoExpiryAlarm(String jsonStr) async {
    try {
      final root = jsonDecode(jsonStr);
      if (root is! Map) return;
      final events = root['events'];
      if (events is! List) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      int? next;
      for (final raw in events) {
        if (raw is! Map) continue;
        final until = int.tryParse('${raw['visibleUntilMs']}');
        if (until != null && until > now) {
          next = next == null ? until : math.min(next, until);
        }
      }
      if (next != null) {
        await WidgetAndroidAlarmSync.scheduleExpiryAlarm(next);
      }
    } catch (_) {}
  }

  /// Refresh coalescido: 1 imediato + 1 follow-up só se ainda pendente (~400 ms).
  static void scheduleWidgetRefresh(String authUid) {
    if (authUid.isEmpty) return;
    if (!_isNativeMobile && !kIsWeb) return;

    _payloadStale = true;
    unawaited(_refreshNow(authUid, preferCache: true, bypassThrottle: true));

    _widgetFollowUpTimer?.cancel();
    _widgetFollowUpTimer = Timer(const Duration(milliseconds: 400), () {
      if (!_payloadStale) return;
      unawaited(_refreshNow(authUid, preferCache: true, bypassThrottle: true));
    });
  }

  /// Resume: refresh leve via cache local (live sync cobre alterações com app aberto).
  static void refreshOnResumeIfNeeded(String authUid) {
    if (authUid.isEmpty) return;
    if (!_isNativeMobile && !kIsWeb) return;
    scheduleWidgetRefresh(authUid);
  }

  /// Confirmação pós-salvar — pula se o refresh imediato já concluiu.
  static Future<void> refreshWidgetIfStale(String authUid) {
    if (authUid.isEmpty) return Future.value();

    if (!_payloadStale) return Future.value();

    return refreshWidgetImmediately(authUid);
  }

  static Future<void> refreshWidgetImmediately(String authUid) {
    if (authUid.isEmpty) return Future.value();

    if (!_isNativeMobile && !kIsWeb) return Future.value();

    _payloadStale = true;

    _pendingForceUid = null;

    return _refreshNow(
      authUid,
      preferCache: true,
      bypassThrottle: true,
    );
  }

  /// Ao voltar a internet: atualiza widget em background sem bloquear UI.
  static void silentResyncAfterReconnect(String authUid) {
    if (authUid.isEmpty) return;
    if (!_isNativeMobile && !kIsWeb) return;
    unawaited(() async {
      if (!await _networkLikelyAvailable()) return;
      await _refreshNow(
        authUid,
        preferCache: false,
        bypassThrottle: true,
      );
    }());
  }

  static Future<void> forceUpdateWidgetData(String authUid) async {
    scheduleWidgetRefresh(authUid);
  }

  static Future<void> _refreshNow(
    String passedUid, {
    bool preferCache = false,
    bool bypassThrottle = false,
  }) async {
    if (_updateFuture != null) {
      _pendingForceUid = passedUid;

      return _updateFuture;
    }

    _updateFuture = _refreshNowImpl(
      passedUid,
      preferCache: preferCache,
      bypassThrottle: bypassThrottle,
    ).whenComplete(() {
      _updateFuture = null;

      final pending = _pendingForceUid;

      if (pending != null && pending.isNotEmpty) {
        _pendingForceUid = null;

        unawaited(
            _refreshNow(pending, preferCache: true, bypassThrottle: true));
      }
    });

    return _updateFuture!;
  }

  static Future<void> _refreshNowImpl(
    String passedUid, {
    bool preferCache = false,
    bool bypassThrottle = false,
  }) async {
    try {
      await _ensureAppGroup();

      final fsUid = firestoreUserDocIdForAppShell(passedUid);

      if (fsUid.isEmpty) return;

      final fetched = await Future.wait<Object>([
        _fetchScaleEvents(
          fsUid,
          preferCache: true,
          bypassThrottle: bypassThrottle,
        ),
        _fetchReminderEvents(
          fsUid,
          preferCache: true,
          bypassThrottle: bypassThrottle,
        ),
        _fetchFinancePendingAsEvents(
          fsUid,
          preferCache: true,
          bypassThrottle: bypassThrottle,
        ),
      ]);

      final scaleEvents = fetched[0] as List<WidgetDayEvent>;

      final reminderEvents = fetched[1] as List<WidgetDayEvent>;

      final financeEvents = fetched[2] as List<WidgetDayEvent>;

      final events = _mergeEvents(scaleEvents, reminderEvents, financeEvents);

      String jsonStr;

      final emptyIsolateInput = <String, dynamic>{
        'events': <Map<String, dynamic>>[],
        'financeItems': <Map<String, dynamic>>[],
        'financeRaw': '',
        'nowMs': DateTime.now().millisecondsSinceEpoch,
      };

      if (events.isEmpty) {
        // Só reutiliza cache antigo offline — nunca após exclusão / sync forçada.
        final allowStaleCache = preferCache && !bypassThrottle;
        if (allowStaleCache) {
          final cached = WidgetNativePayloadCache.peekJson(fsUid);
          if (cached != null && cached.isNotEmpty) {
            jsonStr = cached;
          } else {
            jsonStr =
                await compute(encodeNativeWidgetPayload, emptyIsolateInput);
          }
        } else {
          jsonStr = await compute(encodeNativeWidgetPayload, emptyIsolateInput);
        }
      } else {
        final isolateInput = <String, dynamic>{
          'events': events.map((e) => e.toIsolateMap()).toList(),
          'financeItems': <Map<String, dynamic>>[],
          'financeRaw': '',
          'nowMs': DateTime.now().millisecondsSinceEpoch,
        };

        jsonStr = await compute(encodeNativeWidgetPayload, isolateInput);
      }

      if (!_payloadStale && jsonStr == _lastJsonPayload && !bypassThrottle) {
        _lastUpdateAt = DateTime.now();
        return;
      }

      _payloadStale = false;
      _lastJsonPayload = jsonStr;

      if (kIsWeb) {
        unawaited(WidgetNativePayloadCache.save(fsUid, jsonStr));
        _lastUpdateAt = DateTime.now();
        unawaited(WidgetLastSyncPrefs.saveNow(_lastUpdateAt));
        return;
      }

      await _persistNativeWidget(jsonStr);

      unawaited(WidgetNativePayloadCache.save(fsUid, jsonStr));

      _lastUpdateAt = DateTime.now();
      unawaited(WidgetLastSyncPrefs.saveNow(_lastUpdateAt));
    } catch (_) {}
  }
}

typedef WidgetDataService = WidgetUpdateService;
