import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../constants/google_oauth_config.dart';
import '../utils/firestore_web_guard.dart';
import 'google_calendar_auth_helper.dart';

/// Evento externo do Google Calendar (somente leitura na Agenda).
class GoogleCalendarEventItem {
  const GoogleCalendarEventItem({
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

class GoogleCalendarEnableResult {
  const GoogleCalendarEnableResult._({
    required this.ok,
    this.email,
    this.message,
    this.cancelled = false,
  });

  final bool ok;
  final String? email;
  final String? message;
  final bool cancelled;

  factory GoogleCalendarEnableResult.success(String email) =>
      GoogleCalendarEnableResult._(ok: true, email: email);

  factory GoogleCalendarEnableResult.fail(String message) =>
      GoogleCalendarEnableResult._(ok: false, message: message);

  factory GoogleCalendarEnableResult.cancelledByUser() =>
      const GoogleCalendarEnableResult._(ok: false, cancelled: true);
}

/// Integração Google Calendar: leitura para colorir dias e escrita ao salvar compromissos.
class GoogleCalendarSyncService {
  GoogleCalendarSyncService._();

  static const calendarScope = GoogleOAuthConfig.calendarScope;
  static const googleEventColor = Color(0xFF4285F4);

  static String? _activeConnectedEmail;

  /// Só importa/sincroniza a partir desta data — evita encher a Agenda com histórico antigo.
  static final DateTime syncMinDate = DateTime(2026, 6, 1);

  static bool isOnOrAfterSyncMin(DateTime d) {
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(syncMinDate);
  }

  static List<GoogleCalendarEventItem> _filterEventsFromSyncMin(
    List<GoogleCalendarEventItem> events,
  ) {
    return events.where((e) => isOnOrAfterSyncMin(e.day)).toList();
  }

  static DocumentReference<Map<String, dynamic>> _settingsRef(String uid) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('settings')
          .doc('google_calendar_integration');

  static Future<bool> isEnabled(String uid) async {
    if (uid.isEmpty) return false;
    final snap = await _settingsRef(uid).get();
    return snap.data()?['enabled'] == true;
  }

  static Stream<bool> enabledStream(String uid) {
    if (uid.isEmpty) return Stream<bool>.value(false);
    return _settingsRef(uid)
        .snapshots()
        .map((s) => s.data()?['enabled'] == true);
  }

  static Stream<String?> connectedEmailStream(String uid) {
    if (uid.isEmpty) return Stream<String?>.value(null);
    return _settingsRef(uid).snapshots().map(
          (s) => (s.data()?['connectedEmail'] ?? '').toString().trim().isEmpty
              ? null
              : (s.data()?['connectedEmail'] ?? '').toString().trim(),
        );
  }

  /// Ativa: reutiliza login Google (Web/Firebase) ou vincula Gmail se entrou com Apple.
  static Future<GoogleCalendarEnableResult> enable(String uid) async {
    if (uid.isEmpty) {
      return GoogleCalendarEnableResult.fail('Sessão inválida. Entre novamente.');
    }

    final firebaseUser = FirebaseAuth.instance.currentUser;
    final loginEmail = (firebaseUser?.email ?? '').trim();
    final settingsSnap = await _settingsRef(uid).get();
    final storedEmail =
        (settingsSnap.data()?['connectedEmail'] ?? '').toString().trim();
    final preferredEmail = storedEmail.isNotEmpty
        ? storedEmail
        : (GoogleCalendarAuthHelper.isApplePrimaryLogin() ? null : loginEmail);

    try {
      final auth = await GoogleCalendarAuthHelper.requestInteractive(
        preferredEmail: (preferredEmail == null || preferredEmail.isEmpty)
            ? null
            : preferredEmail,
      );

      if (auth.cancelled) {
        return GoogleCalendarEnableResult.cancelledByUser();
      }
      if (!auth.ok) {
        return GoogleCalendarEnableResult.fail(
          auth.errorMessage ?? 'Não foi possível conectar ao Google Calendar.',
        );
      }

      final token = auth.accessToken!;
      if (!await _testCalendarAccess(token)) {
        return GoogleCalendarEnableResult.fail(
          'Sem acesso ao Google Calendar. Verifique se a conta '
          '${auth.email ?? 'Google'} autorizou o WISDOMAPP.',
        );
      }

      final connectedEmail = (auth.email ?? preferredEmail ?? loginEmail).trim();
      _activeConnectedEmail = connectedEmail.isEmpty ? null : connectedEmail;

      await FirestoreWebGuard.runWithWebRecovery(() async {
        await _settingsRef(uid).set({
          'enabled': true,
          'provider': 'google_calendar',
          'connectedEmail': _activeConnectedEmail ?? '',
          'loginProviderApple': GoogleCalendarAuthHelper.isApplePrimaryLogin(),
          'connectedAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      });

      unawaited(syncAllLocalReminders(userDocId: uid));

      return GoogleCalendarEnableResult.success(
        _activeConnectedEmail ?? connectedEmail,
      );
    } catch (e, st) {
      debugPrint('GoogleCalendarSyncService.enable: $e\n$st');
      return GoogleCalendarEnableResult.fail(
        'Erro ao conectar: ${e.toString().split('\n').first}',
      );
    }
  }

  static Future<bool> _testCalendarAccess(String token) async {
    // Usa a mesma API dos eventos (escopo calendar.events) — calendarList exige outro escopo.
    final uri = Uri.parse(
      'https://www.googleapis.com/calendar/v3/calendars/primary/events?maxResults=1',
    );
    try {
      final res = await http.get(
        uri,
        headers: {'Authorization': 'Bearer $token'},
      );
      if (res.statusCode >= 200 && res.statusCode < 300) return true;
      debugPrint(
        'GoogleCalendar _testCalendarAccess HTTP ${res.statusCode}: '
        '${res.body.length > 200 ? res.body.substring(0, 200) : res.body}',
      );
      return false;
    } catch (e) {
      debugPrint('GoogleCalendar _testCalendarAccess: $e');
      return false;
    }
  }

  /// Desativa integração (mantém conta Google no dispositivo).
  static Future<void> disable(String uid) async {
    if (uid.isEmpty) return;
    await GoogleCalendarAuthHelper.clearCache();
    _activeConnectedEmail = null;
    await _settingsRef(uid).set({
      'enabled': false,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<String?> _accessToken([String? uid]) async {
    if (_activeConnectedEmail == null && uid != null && uid.isNotEmpty) {
      try {
        final snap = await _settingsRef(uid).get();
        final e = (snap.data()?['connectedEmail'] ?? '').toString().trim();
        if (e.isNotEmpty) _activeConnectedEmail = e;
      } catch (_) {}
    }

    final auth = await GoogleCalendarAuthHelper.requestSilent(
      preferredEmail: _activeConnectedEmail,
    );
    if (auth.ok) return auth.accessToken;
    return GoogleCalendarAuthHelper.cachedTokenIfValid();
  }

  static DateTime _dayKey(DateTime d) => DateTime(d.year, d.month, d.day);

  static List<GoogleCalendarEventItem> _parseEventsResponse(
    Map<String, dynamic> body,
  ) {
    final items = (body['items'] as List<dynamic>?) ?? [];
    final out = <GoogleCalendarEventItem>[];
    for (final raw in items) {
      if (raw is! Map<String, dynamic>) continue;
      final id = (raw['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final title = (raw['summary'] ?? 'Evento Google').toString();
      final notes = (raw['description'] ?? '').toString();
      final startObj = raw['start'] as Map<String, dynamic>?;
      if (startObj == null) continue;

      DateTime? day;
      String timeStart = '';
      String timeEnd = '';
      final endObj = raw['end'] as Map<String, dynamic>?;

      if (startObj['date'] != null) {
        final p = DateTime.tryParse(startObj['date'].toString());
        if (p != null) day = _dayKey(p);
      } else if (startObj['dateTime'] != null) {
        final p = DateTime.tryParse(startObj['dateTime'].toString());
        if (p != null) {
          day = _dayKey(p);
          timeStart = DateFormat('HH:mm').format(p.toLocal());
        }
      }
      if (endObj != null && endObj['dateTime'] != null) {
        final p = DateTime.tryParse(endObj['dateTime'].toString());
        if (p != null) timeEnd = DateFormat('HH:mm').format(p.toLocal());
      }
      if (day == null) continue;

      out.add(
        GoogleCalendarEventItem(
          id: id,
          title: title,
          day: day,
          timeStart: timeStart,
          timeEnd: timeEnd,
          notes: notes,
        ),
      );
    }
    return out;
  }

  /// Eventos do mês (primary calendar), apenas a partir de [syncMinDate] (jun/2026+).
  static Future<List<GoogleCalendarEventItem>> fetchEventsForMonth(
    DateTime month, {
    String? userDocId,
  }) async {
    final monthEnd = DateTime(month.year, month.month + 1, 0, 23, 59, 59);
    if (monthEnd.isBefore(syncMinDate)) return [];

    final token = await _accessToken(userDocId);
    if (token == null) return [];

    final monthStart = DateTime(month.year, month.month, 1);
    final start = monthStart.isBefore(syncMinDate) ? syncMinDate : monthStart;
    final end = monthEnd;
    final fmt = DateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'");
    final uri = Uri.parse(
      'https://www.googleapis.com/calendar/v3/calendars/primary/events'
      '?singleEvents=true'
      '&orderBy=startTime'
      '&timeMin=${Uri.encodeComponent(fmt.format(start.toUtc()))}'
      '&timeMax=${Uri.encodeComponent(fmt.format(end.toUtc()))}',
    );

    try {
      final res = await http.get(uri, headers: {'Authorization': 'Bearer $token'});
      if (res.statusCode < 200 || res.statusCode >= 300) return [];
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return _filterEventsFromSyncMin(_parseEventsResponse(body));
    } catch (e) {
      debugPrint('fetchEventsForMonth: $e');
      return [];
    }
  }

  /// Dias do mês visível que possuem eventos no Google Calendar (primary).
  static Future<Set<DateTime>> fetchBusyDaysForMonth(DateTime month) async {
    final events = await fetchEventsForMonth(month);
    return events.map((e) => e.day).toSet();
  }

  static Map<DateTime, List<GoogleCalendarEventItem>> groupEventsByDay(
    List<GoogleCalendarEventItem> events,
  ) {
    final map = <DateTime, List<GoogleCalendarEventItem>>{};
    for (final e in events) {
      map.putIfAbsent(e.day, () => []).add(e);
    }
    for (final list in map.values) {
      list.sort((a, b) => a.timeStart.compareTo(b.timeStart));
    }
    return map;
  }

  /// Eventos Google do dia que ainda não estão espelhados em `reminders.googleEventId`.
  static List<GoogleCalendarEventItem> externalEventsForDay({
    required DateTime day,
    required List<GoogleCalendarEventItem> googleEvents,
    required Set<String> linkedGoogleEventIds,
  }) {
    final key = _dayKey(day);
    return googleEvents
        .where((e) => _dayKey(e.day) == key && !linkedGoogleEventIds.contains(e.id))
        .toList();
  }

  static String _isoLocal(DateTime date, String hhmm) {
    final parts = hhmm.split(':');
    final h = int.tryParse(parts.first) ?? 0;
    final m = int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0;
    final dt = DateTime(date.year, date.month, date.day, h, m);
    final off = dt.timeZoneOffset;
    final sign = off.isNegative ? '-' : '+';
    final oh = off.inHours.abs().toString().padLeft(2, '0');
    final om = (off.inMinutes.abs() % 60).toString().padLeft(2, '0');
    return '${DateFormat("yyyy-MM-dd'T'HH:mm:ss").format(dt)}$sign$oh:$om';
  }

  /// Envia todos os compromissos locais sem `googleEventId` para o Google Calendar.
  static Future<int> syncAllLocalReminders({required String userDocId}) async {
    if (userDocId.isEmpty || !await isEnabled(userDocId)) return 0;
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(userDocId)
        .collection('reminders')
        .get();
    var n = 0;
    for (final doc in snap.docs) {
      final data = doc.data();
      final type = (data['type'] ?? 'compromisso').toString().toLowerCase();
      if (type != 'compromisso') continue;
      final existing = (data['googleEventId'] ?? '').toString().trim();
      if (existing.isNotEmpty) continue;
      final dateRaw = data['date'];
      DateTime? date;
      if (dateRaw is Timestamp) date = dateRaw.toDate();
      if (date == null || !isOnOrAfterSyncMin(date)) continue;
      await syncReminderToGoogle(
        userDocId: userDocId,
        reminderDocId: doc.id,
        title: (data['title'] ?? 'Compromisso').toString(),
        notes: (data['notes'] ?? '').toString(),
        date: date,
        timeHHmm: (data['time'] ?? '09:00').toString(),
        endTimeHHmm: (data['endTime'] ?? '10:00').toString(),
      );
      n++;
    }
    return n;
  }

  /// Cria/atualiza evento no Google Calendar e grava `googleEventId` no reminder.
  static Future<void> syncReminderToGoogle({
    required String userDocId,
    required String reminderDocId,
    required String title,
    required String notes,
    required DateTime date,
    required String timeHHmm,
    required String endTimeHHmm,
  }) async {
    if (userDocId.isEmpty || reminderDocId.isEmpty) return;
    if (!await isEnabled(userDocId)) return;
    if (!isOnOrAfterSyncMin(date)) return;

    final token = await _accessToken(userDocId);
    if (token == null) return;

    final payload = {
      'summary': title,
      'description': notes.isEmpty ? 'Compromisso WISDOMAPP' : notes,
      'start': {
        'dateTime': _isoLocal(date, timeHHmm),
        'timeZone': 'America/Sao_Paulo',
      },
      'end': {
        'dateTime': _isoLocal(date, endTimeHHmm),
        'timeZone': 'America/Sao_Paulo',
      },
      'colorId': '7',
    };

    final ref = FirebaseFirestore.instance
        .collection('users')
        .doc(userDocId)
        .collection('reminders')
        .doc(reminderDocId);
    final existing = await ref.get();
    final oldEventId = (existing.data()?['googleEventId'] ?? '').toString().trim();

    final uri = oldEventId.isNotEmpty
        ? Uri.parse(
            'https://www.googleapis.com/calendar/v3/calendars/primary/events/${Uri.encodeComponent(oldEventId)}',
          )
        : Uri.parse(
            'https://www.googleapis.com/calendar/v3/calendars/primary/events',
          );

    final res = oldEventId.isNotEmpty
        ? await http.put(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          )
        : await http.post(
            uri,
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(payload),
          );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      debugPrint('syncReminderToGoogle HTTP ${res.statusCode}: ${res.body}');
      return;
    }

    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final eventId = (decoded['id'] ?? '').toString();
    if (eventId.isEmpty) return;

    await ref.set({
      'googleEventId': eventId,
      'googleSyncedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  static Future<void> deleteGoogleEventForReminder({
    required String userDocId,
    required String reminderDocId,
    String? googleEventId,
  }) async {
    if (userDocId.isEmpty) return;
    var eventId = (googleEventId ?? '').trim();
    if (eventId.isEmpty) {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(userDocId)
          .collection('reminders')
          .doc(reminderDocId)
          .get();
      eventId = (snap.data()?['googleEventId'] ?? '').toString().trim();
    }
    if (eventId.isEmpty) return;
    if (!await isEnabled(userDocId)) return;

    final token = await _accessToken(userDocId);
    if (token == null) return;

    final uri = Uri.parse(
      'https://www.googleapis.com/calendar/v3/calendars/primary/events/${Uri.encodeComponent(eventId)}',
    );
    await http.delete(uri, headers: {'Authorization': 'Bearer $token'});
  }
}
