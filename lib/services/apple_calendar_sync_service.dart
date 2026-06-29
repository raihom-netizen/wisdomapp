import 'dart:io' show Platform;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_calendar/device_calendar.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../utils/firestore_web_guard.dart';

/// Evento do Calendário nativo (EventKit — iPhone / iPad).
class AppleCalendarEventItem {
  const AppleCalendarEventItem({
    required this.id,
    required this.title,
    required this.day,
    this.timeStart = '',
    this.timeEnd = '',
    this.notes = '',
  });

  final String id;
  final String title;
  final DateTime day;
  final String timeStart;
  final String timeEnd;
  final String notes;

  String get horarioLabel {
    if (timeStart.isEmpty) return 'Dia inteiro';
    if (timeEnd.isNotEmpty) return '$timeStart – $timeEnd';
    return timeStart;
  }
}

/// Sincronização com **EventKit** (framework oficial Apple — iOS/iPadOS).
///
/// - **App nativo:** leitura/gravação local via EventKit (`device_calendar`).
/// - **Web:** a Apple não expõe API REST para iCloud; integração web→iCloud
///   exigiria **CalDAV** no servidor (fora do escopo do app Flutter web).
/// - **Google Calendar:** use OAuth (painel unificado) em web/Android/iOS.
class AppleCalendarSyncService {
  AppleCalendarSyncService._();

  static const appleEventColor = Color(0xFFFF3B30);
  static final DeviceCalendarPlugin _plugin = DeviceCalendarPlugin();
  static String? _defaultCalendarId;
  static bool _timeZonesReady = false;

  static void _ensureTimeZones() {
    if (_timeZonesReady) return;
    tz_data.initializeTimeZones();
    _timeZonesReady = true;
  }

  static bool get isPlatformSupported =>
      !kIsWeb && Platform.isIOS;

  static DocumentReference<Map<String, dynamic>> _settingsRef(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('apple_calendar_integration');

  static Future<bool> isEnabled(String uid) async {
    if (!isPlatformSupported || uid.isEmpty) return false;
    try {
      final snap = await _settingsRef(uid).get();
      return snap.data()?['enabled'] == true;
    } catch (_) {
      return false;
    }
  }

  static Stream<bool> enabledStream(String uid) {
    if (!isPlatformSupported || uid.isEmpty) {
      return Stream<bool>.value(false);
    }
    return _settingsRef(uid).snapshots().map((s) => s.data()?['enabled'] == true);
  }

  static Future<({bool enabled, bool permissionGranted})> readState(
    String uid,
  ) async {
    if (!isPlatformSupported || uid.isEmpty) {
      return (enabled: false, permissionGranted: false);
    }
    try {
      final snap = await _settingsRef(uid).get();
      return (
        enabled: snap.data()?['enabled'] == true,
        permissionGranted: snap.data()?['permissionGranted'] == true,
      );
    } catch (_) {
      return (enabled: false, permissionGranted: false);
    }
  }

  /// Ativa: pede permissão iOS uma vez; depois sync silencioso.
  static Future<({bool ok, String? message})> enable(String uid) async {
    if (!isPlatformSupported) {
      return (ok: false, message: 'Disponível apenas no iPhone/iPad.');
    }
    if (uid.isEmpty) {
      return (ok: false, message: 'Sessão inválida.');
    }

    _ensureTimeZones();
    final granted = await _requestPermission();
    if (!granted) {
      return (
        ok: false,
        message: 'Permissão do Calendário negada. Ative em Ajustes > WISDOMAPP.',
      );
    }

    final calId = await _resolveDefaultCalendarId(uid);
    if (calId == null) {
      return (ok: false, message: 'Nenhum calendário gravável encontrado.');
    }

    await FirestoreWebGuard.runFirestoreOpSafe(() async {
      await _settingsRef(uid).set({
        'enabled': true,
        'permissionGranted': true,
        'defaultCalendarId': calId,
        'provider': 'apple_eventkit',
        'connectedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });

    return (ok: true, message: null);
  }

  static Future<void> disable(String uid) async {
    if (uid.isEmpty) return;
    _defaultCalendarId = null;
    await FirestoreWebGuard.runFirestoreOpSafe(() async {
      await _settingsRef(uid).set({
        'enabled': false,
        'disabledAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  }

  static Future<bool> warmUpIfEnabled(String uid) async {
    if (!await isEnabled(uid)) return false;
    return _requestPermission();
  }

  static Future<bool> _requestPermission() async {
    try {
      final has = await _plugin.hasPermissions();
      if (has.isSuccess && has.data == true) return true;
      final r = await _plugin.requestPermissions();
      return r.isSuccess && r.data == true;
    } catch (e, st) {
      debugPrint('AppleCalendar permission: $e\n$st');
      return false;
    }
  }

  static Future<String?> _resolveDefaultCalendarId(String uid) async {
    if (_defaultCalendarId != null) return _defaultCalendarId;
    try {
      final snap = await _settingsRef(uid).get();
      final stored = (snap.data()?['defaultCalendarId'] ?? '').toString().trim();
      if (stored.isNotEmpty) {
        _defaultCalendarId = stored;
        return stored;
      }
    } catch (_) {}

    final res = await _plugin.retrieveCalendars();
    if (!res.isSuccess || res.data == null) return null;
    Calendar? pick;
    for (final c in res.data!) {
      if (c.isReadOnly == true) continue;
      if (c.isDefault == true) {
        pick = c;
        break;
      }
      pick ??= c;
    }
    _defaultCalendarId = pick?.id;
    return _defaultCalendarId;
  }

  static Future<String?> _calendarIdForUser(String uid) async {
    return _resolveDefaultCalendarId(uid);
  }

  static Future<List<AppleCalendarEventItem>> fetchEventsForMonth(
    DateTime month, {
    required String userDocId,
  }) async {
    if (!isPlatformSupported || !await isEnabled(userDocId)) return [];
    if (!await _requestPermission()) return [];

    final calId = await _calendarIdForUser(userDocId);
    if (calId == null) return [];

    final start = DateTime(month.year, month.month, 1);
    final end = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    try {
      final res = await _plugin.retrieveEvents(
        calId,
        RetrieveEventsParams(startDate: start, endDate: end),
      );
      if (!res.isSuccess || res.data == null) return [];

      final fmt = DateFormat('HH:mm');
      final out = <AppleCalendarEventItem>[];
      for (final e in res.data!) {
        final startDt = e.start;
        if (startDt == null) continue;
        final local = startDt.toLocal();
        final endDt = e.end?.toLocal();
        out.add(
          AppleCalendarEventItem(
            id: e.eventId ?? '${local.millisecondsSinceEpoch}',
            title: (e.title ?? 'Compromisso').trim(),
            day: DateTime(local.year, local.month, local.day),
            timeStart: e.allDay == true ? '' : fmt.format(local),
            timeEnd: endDt != null && e.allDay != true ? fmt.format(endDt) : '',
            notes: (e.description ?? '').trim(),
          ),
        );
      }
      return out;
    } catch (e, st) {
      debugPrint('AppleCalendar fetch: $e\n$st');
      return [];
    }
  }

  static Map<DateTime, List<AppleCalendarEventItem>> groupEventsByDay(
    List<AppleCalendarEventItem> events,
  ) {
    final map = <DateTime, List<AppleCalendarEventItem>>{};
    for (final e in events) {
      final k = DateTime(e.day.year, e.day.month, e.day.day);
      map.putIfAbsent(k, () => []).add(e);
    }
    return map;
  }

  /// Grava compromisso no Calendário Apple (silencioso após permissão).
  static Future<bool> syncReminder({
    required String userDocId,
    required String reminderDocId,
    required String title,
    required String notes,
    required DateTime date,
    required String timeHHmm,
    required String endTimeHHmm,
  }) async {
    if (!await isEnabled(userDocId)) return false;
    _ensureTimeZones();
    if (!await _requestPermission()) return false;

    final calId = await _calendarIdForUser(userDocId);
    if (calId == null) return false;

    DateTime start;
    DateTime end;
    final allDay = timeHHmm.trim().isEmpty;
    if (allDay) {
      start = DateTime(date.year, date.month, date.day);
      end = DateTime(date.year, date.month, date.day, 23, 59);
    } else {
      start = _combineDateTime(date, timeHHmm);
      end = endTimeHHmm.trim().isNotEmpty
          ? _combineDateTime(date, endTimeHHmm)
          : start.add(const Duration(hours: 1));
    }

    try {
      final event = Event(calId)
        ..title = title
        ..description = notes
        ..start = tz.TZDateTime.from(start, tz.local)
        ..end = tz.TZDateTime.from(end, tz.local)
        ..allDay = allDay;

      final existingId = await _storedAppleEventId(userDocId, reminderDocId);
      if (existingId != null && existingId.isNotEmpty) {
        event.eventId = existingId;
      }

      final res = await _plugin.createOrUpdateEvent(event);
      if (res == null) return false;
      if (res.isSuccess && res.data != null && res.data!.isNotEmpty) {
        await _saveAppleEventId(userDocId, reminderDocId, res.data!);
        return true;
      }
      return res.isSuccess;
    } catch (e, st) {
      debugPrint('AppleCalendar syncReminder: $e\n$st');
      return false;
    }
  }

  static DateTime _combineDateTime(DateTime date, String hhmm) {
    final p = hhmm.split(':');
    final h = int.tryParse(p.first) ?? 0;
    final m = p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0;
    return DateTime(date.year, date.month, date.day, h, m);
  }

  static Future<String?> _storedAppleEventId(String uid, String reminderId) async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reminders')
          .doc(reminderId)
          .get();
      final raw = (snap.data()?['appleEventId'] ?? '').toString().trim();
      return raw.isEmpty ? null : raw;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveAppleEventId(
    String uid,
    String reminderId,
    String appleEventId,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('reminders')
          .doc(reminderId)
          .set({'appleEventId': appleEventId}, SetOptions(merge: true));
    } catch (_) {}
  }
}
