import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/notification_center_entry.dart';
import 'notification_module_theme.dart';

/// Persistência local leve: dismiss manual + inbox de push (sem gravar Firestore).
class NotificationCenterStore {
  NotificationCenterStore._();

  static final NotificationCenterStore instance = NotificationCenterStore._();

  static const String _dismissedKey = 'wisdom_notification_center_dismissed_v1';
  static const String _pushInboxKey =
      'wisdom_notification_center_push_inbox_v1';
  static const int _maxPushInbox = 48;
  static const Duration _retention = Duration(days: 1);

  final ValueNotifier<int> revision = ValueNotifier<int>(0);

  Set<String> _dismissed = {};
  List<Map<String, dynamic>> _pushInbox = [];
  bool _loaded = false;
  bool _saving = false;

  /// Carrega dados do SharedPreferences uma única vez; as leituras seguintes usam cache.
  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final dismissedRaw = prefs.getStringList(_dismissedKey) ?? const [];
    _dismissed = dismissedRaw.toSet();
    final inboxRaw = prefs.getString(_pushInboxKey);
    if (inboxRaw != null && inboxRaw.isNotEmpty) {
      try {
        final list = jsonDecode(inboxRaw);
        if (list is List) {
          _pushInbox = list
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList();
        }
      } catch (_) {
        _pushInbox = [];
      }
    }
    _prunePushInbox(DateTime.now());
    _loaded = true;
  }

  /// Pré-carrega os dados em memória (chamar no startup para evitar latency na 1ª notificação).
  Future<void> warmUp() => _ensureLoaded();

  void _bump() => revision.value++;

  /// Persiste inbox + dismissed com debounce (evita múltiplas escritas seguidas).
  Timer? _saveDebounce;
  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 120), () {
      unawaited(_flushToPrefs());
    });
  }

  Future<void> _flushToPrefs() async {
    if (_saving) return;
    _saving = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.setStringList(_dismissedKey, _dismissed.toList()),
        prefs.setString(_pushInboxKey, jsonEncode(_pushInbox)),
      ]);
    } finally {
      _saving = false;
    }
  }

  Future<Set<String>> dismissedIds() async {
    await _ensureLoaded();
    return Set<String>.from(_dismissed);
  }

  Future<List<NotificationCenterEntry>> pushInboxEntries() async {
    await _ensureLoaded();
    final now = DateTime.now();
    _prunePushInbox(now);
    return _pushInbox
        .map(NotificationCenterEntry.fromPushInboxMap)
        .where((e) => !_dismissed.contains(e.id))
        .toList();
  }

  bool isDismissedSync(String id) => _dismissed.contains(id);

  Future<void> dismiss(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    await _ensureLoaded();
    var changed = false;
    for (final id in ids) {
      if (id.isEmpty) continue;
      if (_dismissed.add(id)) changed = true;
    }
    if (!changed) return;
    _scheduleSave();
    _bump();
  }

  Future<void> dismissAll(Iterable<String> ids) => dismiss(ids);

  /// Pós-reconexão: poda inbox local e notifica ouvintes sem UI de sync.
  Future<void> silentResyncAfterReconnect() async {
    await _ensureLoaded();
    final before = _pushInbox.length;
    _prunePushInbox(DateTime.now());
    if (_pushInbox.length != before) {
      _scheduleSave();
    }
    _bump();
  }

  /// Registra lembrete local exibido na bandeja — sincroniza com a central.
  Future<void> recordLocalDelivery({
    required String dedupeKey,
    required String title,
    required String body,
    String? channelKind,
  }) async {
    if (title.trim().isEmpty && body.trim().isEmpty) return;
    final id = dedupeKey.isNotEmpty
        ? 'local:$dedupeKey'
        : 'local:${DateTime.now().microsecondsSinceEpoch}';
    await _ensureLoaded();
    if (_dismissed.contains(id)) return;

    final entry = {
      'id': id,
      'kind': (channelKind ?? '').toString(),
      'title': title.trim().isEmpty ? 'WISDOMAPP' : title.trim(),
      'body': body.trim(),
      'notifiedAt': DateTime.now().toIso8601String(),
    };

    _pushInbox.removeWhere((e) => e['id'] == id);
    _pushInbox.insert(0, entry);
    if (_pushInbox.length > _maxPushInbox) {
      _pushInbox = _pushInbox.take(_maxPushInbox).toList();
    }
    _prunePushInbox(DateTime.now());

    _scheduleSave();
    _bump();
  }

  static String? channelKindFromLocalPayload(String payload) {
    for (final part in payload.split('|')) {
      if (part.startsWith('cat:')) {
        return part.substring(4);
      }
    }
    return null;
  }

  /// Registra push recebido — operação O(1) em memória + gravação assíncrona.
  Future<void> recordPush(RemoteMessage message) async {
    final d = message.data;
    final title =
        (message.notification?.title ?? d['title'] ?? '').toString().trim();
    final body =
        (message.notification?.body ?? d['body'] ?? '').toString().trim();
    if (title.isEmpty && body.isEmpty) return;

    final kind = NotificationModuleTheme.resolveKindFromData(d);
    final alertId = (d['alertId'] ?? d['sourceId'] ?? '').toString().trim();
    final id = alertId.isNotEmpty
        ? 'agenda:$alertId'
        : 'push:${message.messageId ?? DateTime.now().microsecondsSinceEpoch}';

    await _ensureLoaded();
    if (_dismissed.contains(id)) return;

    final entry = {
      'id': id,
      'kind': kind,
      'title': title.isEmpty ? 'WISDOMAPP' : title,
      'body': body,
      'notifiedAt': DateTime.now().toIso8601String(),
      if ((d['linkLocalizacao'] ?? '').toString().trim().isNotEmpty)
        'linkLocalizacao': (d['linkLocalizacao'] ?? '').toString().trim(),
      if ((d['contatoWhatsApp'] ?? '').toString().trim().isNotEmpty)
        'contatoWhatsApp': (d['contatoWhatsApp'] ?? '').toString().trim(),
    };

    _pushInbox.removeWhere((e) => e['id'] == id);
    _pushInbox.insert(0, entry);
    if (_pushInbox.length > _maxPushInbox) {
      _pushInbox = _pushInbox.take(_maxPushInbox).toList();
    }
    _prunePushInbox(DateTime.now());

    _scheduleSave();
    _bump();
  }

  void _prunePushInbox(DateTime now) {
    final cutoff = now.subtract(_retention);
    _pushInbox = _pushInbox.where((m) {
      final raw = m['notifiedAt']?.toString();
      if (raw == null || raw.isEmpty) return false;
      final at = DateTime.tryParse(raw);
      if (at == null) return false;
      return !at.isBefore(cutoff);
    }).toList();
  }
}
